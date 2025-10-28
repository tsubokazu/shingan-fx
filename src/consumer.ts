interface TvQueueMessage {
	signal: string;
	symbol_raw: string;
	symbol_norm: string;
	timeframe: string;
	price?: string | number;
	chart?: string;
	bar_time: string;
	idem: string;
	received_at: number;
	source_ip: string;
	user_agent: string;
	metadata: Record<string, unknown>;
}

interface QueueMessage<T> {
	body: T;
	ack(): Promise<void>;
	retry(): Promise<void>;
}

interface MessageBatch<T> {
	queue: string;
	messages: QueueMessage<T>[];
}

interface Env {
	IDEMPOTENCY_KV: KVNamespace;
	RATELIMIT_KV: KVNamespace;
	MAPPING_KV: KVNamespace;
	PENDING_SIGNALS_KV: KVNamespace;
	MIN_INTERVAL_MS?: string;
	DEFAULT_LOT?: string;
	TP_CLOSE_RATIO?: string;
}

const PENDING_TTL_SECONDS = 60 * 60 * 24; // 24 hours

interface TradeDirective {
	type: 'OPEN' | 'CLOSE' | 'CLOSE_PARTIAL';
	side?: 'BUY' | 'SELL';
	volume?: number;
	comment?: string;
	volume_ratio?: number;
}

function getDefaultLot(env: Env): number {
	const parsed = parseFloat(env.DEFAULT_LOT ?? '0');
	return Number.isFinite(parsed) && parsed > 0 ? parsed : 0.1;
}

function getTpCloseRatio(env: Env): number {
	const parsed = parseFloat(env.TP_CLOSE_RATIO ?? '0');
	if (Number.isFinite(parsed) && parsed > 0 && parsed <= 1) {
		return parsed;
	}
	return 0.5;
}

function decideAction(message: TvQueueMessage, env: Env): TradeDirective | null {
	const signalUpper = message.signal.toUpperCase();
	const baseComment = `${signalUpper}_${message.timeframe}`;

	switch (signalUpper) {
		case 'LONG':
			return {
				type: 'OPEN',
				side: 'BUY',
				volume: getDefaultLot(env),
				comment: baseComment,
			};
		case 'SHORT':
			return {
				type: 'OPEN',
				side: 'SELL',
				volume: getDefaultLot(env),
				comment: baseComment,
			};
		case 'TP':
		case 'TP_LONG':
		case 'TP_SHORT':
			return {
				type: 'CLOSE_PARTIAL',
				volume_ratio: getTpCloseRatio(env),
				comment: baseComment,
			};
		default:
			return null;
	}
}

async function isDuplicate(env: Env, key: string): Promise<boolean> {
	const exists = await env.IDEMPOTENCY_KV.get(key);
	if (exists) {
		return true;
	}
	await env.IDEMPOTENCY_KV.put(key, '1', { expirationTtl: 600 });
	return false;
}

async function mapSymbol(env: Env, symbol: string): Promise<string> {
	const mapped = await env.MAPPING_KV.get(symbol);
	return mapped ?? symbol;
}

async function rateLimited(env: Env, symbol: string, now: number): Promise<boolean> {
	const minInterval = parseInt(env.MIN_INTERVAL_MS ?? '0', 10);
	if (!Number.isFinite(minInterval) || minInterval <= 0) {
		return false;
	}
	const last = await env.RATELIMIT_KV.get(symbol);
	if (last) {
		const delta = now - parseInt(last, 10);
		if (Number.isFinite(delta) && delta < minInterval) {
			return true;
		}
	}
	await env.RATELIMIT_KV.put(symbol, String(now), { expirationTtl: 3600 });
	return false;
}

async function storePendingSignal(env: Env, key: string, record: Record<string, unknown>): Promise<void> {
	await env.PENDING_SIGNALS_KV.put(key, JSON.stringify(record), {
		expirationTtl: PENDING_TTL_SECONDS,
	});
}

export default {
	async queue(batch: MessageBatch<TvQueueMessage>, env: Env): Promise<void> {
		for (const message of batch.messages) {
			const body = message.body;
			try {
				if (await isDuplicate(env, body.idem)) {
					await message.ack();
					continue;
				}

				const mappedSymbol = await mapSymbol(env, body.symbol_norm);
				const now = Date.now();
				if (await rateLimited(env, mappedSymbol, now)) {
					console.log('rate_limited', {
						symbol: mappedSymbol,
						signal: body.signal,
						bar_time: body.bar_time,
					});
					await message.ack();
					continue;
				}

				const directive = decideAction(body, env);
				if (!directive) {
					console.log('no_action', body);
					await message.ack();
					continue;
				}

				const timestamp = now;
				const pendingKey = `pending:${mappedSymbol}:${String(timestamp).padStart(13, '0')}:${body.idem}`;
				const record = {
					id: body.idem,
					key: pendingKey,
					timestamp,
					symbol: mappedSymbol,
					signal: body.signal,
					action: directive.type === 'OPEN' ? directive.side : directive.type,
					volume: directive.volume,
					volume_ratio: directive.volume_ratio,
					timeframe: body.timeframe,
					bar_time: body.bar_time,
					price: body.price,
					chart: body.chart,
					received_at: body.received_at,
					enqueued_at: now,
					source: {
						ip: body.source_ip,
						user_agent: body.user_agent,
					},
					metadata: {
						...body.metadata,
						comment: directive.comment,
					},
				};

				await storePendingSignal(env, pendingKey, record);
				console.log('pending_signal_stored', {
					key: pendingKey,
					signal: body.signal,
					symbol: mappedSymbol,
				});

				await message.ack();
			} catch (error) {
				console.error('queue_processing_failed', {
					error: (error as Error).message,
					stack: (error as Error).stack,
					body,
				});
				await message.retry();
			}
		}
	},
};
