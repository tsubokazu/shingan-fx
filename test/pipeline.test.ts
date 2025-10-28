import { describe, expect, it, vi, beforeEach } from 'vitest';
import worker from '../src/index';
import consumer from '../src/consumer';

class InMemoryKV implements KVNamespace {
	private store = new Map<string, string>();

	async put(key: string, value: string, _options?: KVNamespacePutOptions): Promise<void> {
		this.store.set(key, value);
	}

	async get(key: string, options?: KVNamespaceGetOptions): Promise<any> {
		const value = this.store.get(key);
		if (value === undefined) {
			return null;
		}
		if (options?.type === 'json') {
			return JSON.parse(value);
		}
		return value;
	}

	async delete(key: string): Promise<void> {
		this.store.delete(key);
	}

	async list(options?: KVNamespaceListOptions): Promise<KVNamespaceListResult<string>> {
		const prefix = options?.prefix ?? '';
		const limit = options?.limit ?? 1000;
		const filtered = Array.from(this.store.keys()).filter((key) => key.startsWith(prefix));
		const selected = filtered.slice(0, limit);
		return {
			keys: selected.map((name) => ({ name })),
			cursor: null,
			list_complete: selected.length === filtered.length,
		};
	}
}

class TestQueue<T> implements Queue<T> {
	public messages: T[] = [];

	async send(message: T): Promise<void> {
		this.messages.push(message);
	}
}

describe('pull pipeline', () => {
	let tvQueue: TestQueue<any>;
let kvIdempotent: InMemoryKV;
let kvRate: InMemoryKV;
let kvMap: InMemoryKV;
let kvPending: InMemoryKV;
	const WEBHOOK_TOKEN = 'webhook-secret';
	const POLL_TOKEN = 'poll-secret';

	beforeEach(() => {
		tvQueue = new TestQueue();
		kvIdempotent = new InMemoryKV();
		kvRate = new InMemoryKV();
		kvMap = new InMemoryKV();
		kvPending = new InMemoryKV();
	});

	it('enqueues webhook, stores pending signals, and serves poll/ack', async () => {
		const webhookEnv = {
			WEBHOOK_TOKEN,
			POLL_TOKEN,
			TV_QUEUE: tvQueue,
			PENDING_SIGNALS_KV: kvPending,
		};

		const webhookPayload = {
			signal: 'LONG',
			symbol: 'EURUSD',
			timeframe: '15',
			price: '1.2345',
			bar_time: '2025-10-27T10:00:00Z',
		};

		const webhookRequest = new Request('https://example.com/', {
			method: 'POST',
			headers: {
				authorization: `Bearer ${WEBHOOK_TOKEN}`,
				'content-type': 'application/json',
			},
			body: JSON.stringify(webhookPayload),
		});

		const webhookResponse = await worker.fetch(webhookRequest, webhookEnv, {} as ExecutionContext);
		expect(webhookResponse.status).toBe(200);
		expect(tvQueue.messages.length).toBe(1);

		const queueMessage = tvQueue.messages[0];
		const ack = vi.fn().mockResolvedValue(undefined);
		const retry = vi.fn().mockResolvedValue(undefined);

		await consumer.queue(
			{
				queue: 'tv_signals',
				messages: [
					{
						body: queueMessage,
						ack,
						retry,
					},
				],
			},
			{
				IDEMPOTENCY_KV: kvIdempotent,
				RATELIMIT_KV: kvRate,
				MAPPING_KV: kvMap,
				PENDING_SIGNALS_KV: kvPending,
				MIN_INTERVAL_MS: '0',
				DEFAULT_LOT: '0.1',
				TP_CLOSE_RATIO: '0.5',
			}
		);

		expect(ack).toHaveBeenCalledOnce();

		const pollEnv = {
			WEBHOOK_TOKEN,
			POLL_TOKEN,
			TV_QUEUE: tvQueue,
			PENDING_SIGNALS_KV: kvPending,
		};

		const pollRequest = new Request('https://example.com/api/poll?symbol=EURUSD', {
			method: 'GET',
			headers: { authorization: `Bearer ${POLL_TOKEN}` },
		});
		const pollResponse = await worker.fetch(pollRequest, pollEnv, {} as ExecutionContext);
		expect(pollResponse.status).toBe(200);
		const pollBody = await pollResponse.json();
		expect(pollBody.items).toHaveLength(1);
		const key = pollBody.items[0].key as string;
		expect(key).toMatch(/^pending:EURUSD:/);

		const ackRequest = new Request('https://example.com/api/ack', {
			method: 'POST',
			headers: {
				authorization: `Bearer ${POLL_TOKEN}`,
				'content-type': 'application/json',
			},
			body: JSON.stringify({ keys: [key] }),
		});
		const ackResponse = await worker.fetch(ackRequest, pollEnv, {} as ExecutionContext);
		expect(ackResponse.status).toBe(200);
		const ackBody = await ackResponse.json();
		expect(ackBody.acknowledged).toBe(1);
		expect(ackBody.missing).toBe(0);

		const pollResponseAfterAck = await worker.fetch(pollRequest, pollEnv, {} as ExecutionContext);
		const pollAfterAckBody = await pollResponseAfterAck.json();
		expect(pollAfterAckBody.items).toHaveLength(0);
	});
});
