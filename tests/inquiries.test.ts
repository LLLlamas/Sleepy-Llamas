import test from 'node:test';
import assert from 'node:assert/strict';
import { inquiryEmailDraft, submitInquiry, validateInquiry, type InquiryInput } from '../src/lib/inquiries.ts';

const valid: InquiryInput = { clientName: ' Alex ', email: 'ALEX@example.com', service: 'general-family-consult', format: 'video', childName: '', stage: 'Due in March', location: '', phone: '', notes: 'Caregiver handoff', website: '', referralSource: 'A friend' };
const receipt = '12345678-1234-4234-8234-123456789abc';

test('requires a configured backend; never pretends to save', async () => {
  await assert.rejects(submitInquiry(null, valid, receipt), /unavailable/);
});
test('successful save requires a durable receipt and sends normalized optional information', async () => {
  let saved: Record<string, unknown> | undefined;
  const id = await submitInquiry({ rpc: async (name, args) => { assert.equal(name, 'sl_create_consultation_inquiry'); saved = args; return { data: { id: receipt }, error: null }; } }, valid, receipt);
  assert.equal(id, receipt);
  assert.deepEqual(saved, { p_request_id: receipt, p_details: { client_name: 'Alex', client_email: 'alex@example.com', service: valid.service, contact_format: 'video', child_name: '', stage: 'Due in March', location: '', client_phone: '', notes: valid.notes, referral_source: 'A friend' }, p_website: '' });
});
test('backend failure or missing receipt never produces success', async () => {
  for (const response of [{data:null,error:{message:'migration not deployed'}},{data:null,error:null},{data:{id:'oops'},error:null},{data:{id:'------------------------------------'},error:null},{data:{id:'99999999-1234-4234-8234-123456789abc'},error:null}]) {
    await assert.rejects(submitInquiry({ rpc: async () => response }, valid, receipt), /could not confirm/);
  }
});
test('a thrown network error is safe to show and preserves the submitted object for retry', async () => {
  const snapshot = { ...valid };
  await assert.rejects(submitInquiry({ rpc: async () => { throw new Error('internal connection detail'); } }, valid, receipt), error => error instanceof Error && error.message.includes('could not confirm') && !error.message.includes('internal'));
  assert.deepEqual(valid, snapshot);
});
test('rate-limit feedback tells the family how to proceed', async () => {
  await assert.rejects(submitInquiry({ rpc: async () => ({ data: null, error: { message: 'inquiry_rate_limit' } }) }, valid, receipt), /try again later/);
});
test('home visits and caregiver training require in-person format and location; child name remains optional', () => {
  assert.deepEqual(validateInquiry(valid), {});
  assert.ok(validateInquiry({ ...valid, service:'home-consult' }).format);
  assert.ok(validateInquiry({ ...valid, service:'caregiver-training' }).format);
  assert.ok(validateInquiry({ ...valid, service:'caregiver-training', format:'in-person' }).location);
  assert.deepEqual(validateInquiry({ ...valid, service:'caregiver-training', format:'in-person', location:'Astoria' }), {});
  assert.ok(validateInquiry({ ...valid, service:'home-consult', format:'in-person' }).location);
  assert.deepEqual(validateInquiry({ ...valid, service:'home-consult', format:'in-person', location:'Astoria' }), {});
});
test('invalid fields and honeypot are rejected before transport', async () => {
  let calls = 0;
  for (const patch of [{ email:'bad' }, { website:'spam' }, { notes:'x'.repeat(2001) }, { service:'made-up' }, { referralSource:'x'.repeat(161) }]) {
    await assert.rejects(submitInquiry({ rpc: async () => { calls++; return {data:{id:receipt},error:null}; } }, { ...valid, ...patch }, receipt));
  }
  assert.equal(calls, 0);
});
test('email fallback is a draft with safely encoded content, not an automatic send', () => {
  const url = inquiryEmailDraft('hello@example.com', { ...valid, childName:'Sam', notes:'Question & details\nNext line?' }, 'Family consult');
  assert.ok(url.startsWith('mailto:hello%40example.com?'));
  const query = new URLSearchParams(url.split('?')[1]);
  assert.equal(query.get('subject'), 'Sleepy Llamas inquiry: Family consult');
  assert.ok(query.get('body')!.includes('Question & details\nNext line?'));
  assert.ok(query.get('body')!.includes('Child name (optional): Sam'));
  assert.ok(query.get('body')!.includes('How I heard about you: A friend'));
});

test('a stalled submission times out honestly and aborts the request when supported', async () => {
  let signal: AbortSignal | undefined;
  const stalled = new Promise<{data:unknown;error:unknown}>(() => {}) as Promise<{data:unknown;error:unknown}> & { abortSignal(signal: AbortSignal): PromiseLike<{data:unknown;error:unknown}> };
  stalled.abortSignal = nextSignal => { signal = nextSignal; return stalled; };
  await assert.rejects(submitInquiry({ rpc: () => stalled }, valid, receipt, 5), /taking longer than expected/);
  assert.equal(signal?.aborted, true);
});
