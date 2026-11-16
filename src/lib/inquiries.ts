/** Small transport boundary: a saved receipt is required before showing success. */
export interface InquiryInput {
  clientName: string;
  email: string;
  service: string;
  format: string;
  childName: string;
  stage: string;
  location: string;
  phone: string;
  notes: string;
  website: string;
  referralSource: string;
}

export type InquiryResponse = { data: unknown; error: unknown };
export interface InquiryRequest extends PromiseLike<InquiryResponse> {
  abortSignal?(signal: AbortSignal): PromiseLike<InquiryResponse>;
}
export interface InquiryClient {
  rpc(name: string, args: Record<string, unknown>): InquiryRequest;
}

export const inquiryServices = [
  'fit-call', 'general-family-consult', 'newborn-postpartum-consult',
  'first-weeks-plan', 'home-consult', 'caregiver-training',
  'overnight-doula', 'overnight-sleep-training', 'not-sure',
] as const;

const formats = ['phone', 'video', 'in-person', 'not-sure'];

export function normalizeInquiry(input: InquiryInput): InquiryInput {
  return Object.fromEntries(Object.entries(input).map(([key, value]) => [key, value.trim()])) as unknown as InquiryInput;
}

export function validateInquiry(raw: InquiryInput): Record<string, string> {
  const input = normalizeInquiry(raw);
  const errors: Record<string, string> = {};
  if (!input.clientName || input.clientName.length > 80) errors.clientName = 'Please enter your name (up to 80 characters).';
  if (input.email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)) errors.email = 'Please enter a valid email address.';
  if (!inquiryServices.some(service => service === input.service)) errors.service = 'Please choose a service, or select “Not sure yet”.';
  if (!formats.includes(input.format)) errors.format = 'Please choose how you would like to meet.';
  if (['home-consult', 'caregiver-training'].includes(input.service) && input.format !== 'in-person') errors.format = 'This appointment takes place in person.';
  if (input.format === 'in-person' && !input.location) errors.location = 'Please share your neighborhood or ZIP code for a visit.';
  for (const [field, max] of Object.entries({ childName: 60, stage: 100, location: 160, phone: 40, notes: 2000, referralSource: 160 })) {
    if (input[field as keyof InquiryInput].length > max) errors[field] = `Please keep this to ${max} characters.`;
  }
  if (input.website) errors.website = 'Please leave the website field empty and try again.';
  return errors;
}

export async function submitInquiry(client: InquiryClient | null, raw: InquiryInput, requestId: string, timeoutMs = 15000): Promise<string> {
  if (!client) throw new Error('The inquiry form is unavailable right now. Please open an email draft below to contact Catalina.');
  const input = normalizeInquiry(raw);
  const errors = validateInquiry(input);
  if (Object.keys(errors).length) throw new Error(Object.values(errors)[0]);
  let response: InquiryResponse;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let timedOut = false;
  const controller = new AbortController();
  try {
    const request = client.rpc('sl_create_consultation_inquiry', {
      p_request_id: requestId,
      p_details: {
        client_name: input.clientName, client_email: input.email.toLowerCase(), service: input.service,
        contact_format: input.format, child_name: input.childName, stage: input.stage,
        location: input.location, client_phone: input.phone, notes: input.notes, referral_source: input.referralSource,
      },
      p_website: input.website,
    });
    const cancellable = request.abortSignal ? request.abortSignal(controller.signal) : request;
    response = await Promise.race([
      cancellable,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => {
          timedOut = true;
          controller.abort();
          reject(new Error('inquiry_timeout'));
        }, timeoutMs);
      }),
    ]);
  } catch {
    if (timedOut) throw new Error('This is taking longer than expected, so we could not confirm your inquiry was saved. Your details are still here. Please retry, or open an email draft below.');
    throw new Error('We could not confirm that your inquiry was saved. Your details are still here. Please retry, or open an email draft below.');
  } finally {
    clearTimeout(timer);
  }
  const { data, error } = response;
  if (error) {
    const message = typeof error === 'object' && error && 'message' in error ? String(error.message) : '';
    if (message.includes('inquiry_rate_limit')) throw new Error('There have been several recent requests. Please try again later, or open an email draft below.');
    throw new Error('We could not confirm that your inquiry was saved. Your details are still here. Please retry, or open an email draft below.');
  }
  if (!data || typeof data !== 'object' || !('id' in data) || typeof data.id !== 'string' || data.id !== requestId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.id)) {
    throw new Error('We could not confirm that your inquiry was saved. Please retry, or open an email draft below.');
  }
  return data.id;
}

export function inquiryEmailDraft(recipient: string, raw: InquiryInput, serviceTitle = raw.service): string {
  const input = normalizeInquiry(raw);
  const subject = `Sleepy Llamas inquiry: ${serviceTitle || 'Family support'}`;
  const body = [
    'Hi Catalina,', '', `My name: ${input.clientName}`, `Reply email: ${input.email}`,
    `Service: ${serviceTitle}`, `Preferred format: ${input.format}`,
    `Child name (optional): ${input.childName}`, `Child age(s) or due date: ${input.stage}`, `Neighborhood / ZIP: ${input.location}`,
    `Phone (optional): ${input.phone}`, `How I heard about you: ${input.referralSource}`, '', 'What I would like help with:', input.notes,
  ].join('\n');
  return `mailto:${encodeURIComponent(recipient)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}
