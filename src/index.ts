interface TvPayload {
	signal?: string;
	symbol?: string;
	symbol_tv?: string;
	timeframe?: string;
	price?: string | number;
	bar_time?: string;
	chart?: string;
	token?: string;
}

interface TvQueueMessage extends Required<Pick<TvPayload, 'signal' | 'bar_time'>> {
	symbol_raw: string;
	symbol_norm: string;
	timeframe: string;
	price?: string | number;
	chart?: string;
	idem: string;
	received_at: number;
	source_ip: string;
	user_agent: string;
	metadata: Record<string, unknown>;
}

interface Env {
	WEBHOOK_TOKEN: string;
	POLL_TOKEN: string;
	TV_QUEUE: Queue<TvQueueMessage>;
	PENDING_SIGNALS_KV: KVNamespace;
}

interface PendingSignalRecord {
	id: string;
	key: string;
	timestamp: number;
	symbol: string;
	signal: string;
	action?: string;
	volume?: number;
	volume_ratio?: number;
	timeframe: string;
	bar_time: string;
	price?: string | number;
	chart?: string;
	received_at: number;
	enqueued_at: number;
	source: {
		ip: string;
		user_agent: string;
	};
	metadata: Record<string, unknown>;
}

async function sha1Hex(input: string): Promise<string> {
	const data = new TextEncoder().encode(input);
	const digest = await crypto.subtle.digest('SHA-1', data);
	return Array.from(new Uint8Array(digest))
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

function normalizeSymbol(payload: TvPayload): string {
	const rawSymbol = (payload.symbol ?? payload.symbol_tv ?? '').trim();
	return rawSymbol.toUpperCase();
}

function normalizeTimeframe(payload: TvPayload): string {
	return (payload.timeframe ?? '').trim().toLowerCase();
}

function extractBearerToken(request: Request): string | null {
	const headerAuth = request.headers.get('authorization');
	if (headerAuth && headerAuth.startsWith('Bearer ')) {
		return headerAuth.slice('Bearer '.length).trim();
	}
	return null;
}

function extractWebhookToken(request: Request, payload: TvPayload): string | null {
	// 1. Try Authorization header (for curl/API clients)
	const headerToken = extractBearerToken(request);
	if (headerToken) return headerToken;

	// 2. Try URL query parameter (for TradingView webhook URL: ?token=XXX)
	const url = new URL(request.url);
	const queryToken = url.searchParams.get('token')?.trim();
	if (queryToken) return queryToken;

	// 3. Try payload token field (for TradingView webhook message body)
	return payload.token?.trim() ?? null;
}

function jsonResponse(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

async function handleWebhook(request: Request, env: Env): Promise<Response> {
	let payload: TvPayload;
	try {
		payload = (await request.json()) as TvPayload;
	} catch (error) {
		return new Response('invalid json', { status: 400 });
	}

	const token = extractWebhookToken(request, payload);
	if (!token || token !== env.WEBHOOK_TOKEN) {
		return new Response('forbidden', { status: 403 });
	}

	const signal = payload.signal?.trim();
	const barTime = payload.bar_time?.trim();
	const symbolNorm = normalizeSymbol(payload);
	const timeframe = normalizeTimeframe(payload);

	if (!signal || !barTime || !symbolNorm || !timeframe) {
		return new Response('missing fields', { status: 400 });
	}

	const idemSource = `${symbolNorm}|${timeframe}|${signal}|${barTime}`;
	const idem = await sha1Hex(idemSource);

	const queueMessage: TvQueueMessage = {
		signal,
		bar_time: barTime,
		symbol_raw: payload.symbol ?? payload.symbol_tv ?? '',
		symbol_norm: symbolNorm,
		timeframe,
		price: payload.price,
		chart: payload.chart,
		idem,
		received_at: Date.now(),
		source_ip: request.headers.get('cf-connecting-ip') ?? '',
		user_agent: request.headers.get('user-agent') ?? '',
		metadata: {
			request_id: crypto.randomUUID(),
		},
	};

	await env.TV_QUEUE.send(queueMessage);

	return jsonResponse({ status: 'queued', idem });
}

function requirePollAuth(request: Request, env: Env): Response | null {
	const token = extractBearerToken(request);
	if (!token || token !== env.POLL_TOKEN) {
		return new Response('unauthorized', { status: 401 });
	}
	return null;
}

async function handlePoll(request: Request, env: Env, url: URL): Promise<Response> {
	const authError = requirePollAuth(request, env);
	if (authError) {
		return authError;
	}

	const symbolParam = url.searchParams.get('symbol')?.trim();
	const symbolFilter = symbolParam ? symbolParam.toUpperCase() : null;
	const limitParam = url.searchParams.get('limit');
	const limitRaw = limitParam ? Number.parseInt(limitParam, 10) : 10;
	const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 100) : 10;

	const prefix = symbolFilter ? `pending:${symbolFilter}:` : 'pending:';
	const listResult = await env.PENDING_SIGNALS_KV.list({ prefix, limit });
	const items: PendingSignalRecord[] = [];

	for (const entry of listResult.keys) {
		const record = (await env.PENDING_SIGNALS_KV.get(entry.name, { type: 'json' })) as
			| PendingSignalRecord
			| null;
		if (record) {
			items.push(record);
		}
	}

	items.sort((a, b) => a.timestamp - b.timestamp);

	return jsonResponse({ items, cursor: listResult.list_complete ? null : listResult.cursor });
}

interface AckPayload {
	keys: string[];
}

async function handleAck(request: Request, env: Env): Promise<Response> {
	const authError = requirePollAuth(request, env);
	if (authError) {
		return authError;
	}

	let payload: AckPayload;
	try {
		payload = (await request.json()) as AckPayload;
	} catch (error) {
		return new Response('invalid json', { status: 400 });
	}

	const keys = Array.isArray(payload.keys) ? payload.keys : [];
	if (keys.length === 0) {
		return new Response('no keys provided', { status: 400 });
	}
	if (keys.length > 200) {
		return new Response('too many keys', { status: 400 });
	}

	let acknowledged = 0;
	let missing = 0;

	await Promise.all(
		keys.map(async (key) => {
			if (!key || !key.startsWith('pending:')) {
				return;
			}
			const value = await env.PENDING_SIGNALS_KV.get(key);
			if (!value) {
				missing += 1;
				return;
			}
			await env.PENDING_SIGNALS_KV.delete(key);
			acknowledged += 1;
		})
	);

	return jsonResponse({ acknowledged, missing });
}

export default {
	async fetch(request, env): Promise<Response> {
		const url = new URL(request.url);

		if (request.method === 'GET' && url.pathname === '/api/poll') {
			return handlePoll(request, env, url);
		}

		if (request.method === 'POST' && url.pathname === '/api/ack') {
			return handleAck(request, env);
		}

		// Webhook endpoint: POST /webhook or POST / (for backwards compatibility)
		// Support both /webhook and /webhook/ (with or without trailing slash)
		const pathname = url.pathname.replace(/\/$/, ''); // Remove trailing slash
		if (request.method === 'POST' && (pathname === '/webhook' || pathname === '')) {
			return handleWebhook(request, env);
		}

		return new Response('not found', { status: 404 });
	},
} satisfies ExportedHandler<Env>;
