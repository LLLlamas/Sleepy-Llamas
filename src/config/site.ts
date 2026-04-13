// ============================================================================
// SITE CONFIG — single source of truth for brand + contact info.
// Edit this file to rebrand or update contact details. Nothing else needs to
// change. All placeholder values are clearly marked with TODO.
// ============================================================================

export const site = {
  // --- Brand ---
  brandName: 'Sleepy Llamas',
  tagline: 'Restful nights for your whole family.',
  shortDescription:
    'Certified overnight doula support and gentle baby sleep training for families in NYC and the greater New York area. Personalized postpartum overnight care delivered with warmth and expertise.',

  // --- Contact (TODO: replace with real values) ---
  email: 'sleepyllamasdoula@gmail.com',
  phone: '(555) 123-4567',              // TODO
  phoneHref: '+15551234567',            // TODO — digits only for tel: links
  serviceArea: 'the New York Area',
  responseTime: 'within 24 hours',

  // --- Payment handles (shown AFTER consultation — informational only) ---
  venmoHandle: '@sleepy-llamas',        // TODO
  zelleHandle: 'sleepyllamasdoula@gmail.com', // TODO — update if using a different Zelle email
  stripePaymentLink: '',                // TODO — paste a Stripe Payment Link URL when ready

  // --- Social (optional, leave empty strings to hide) ---
  instagram: '', // TODO e.g. 'https://instagram.com/sleepyllamas'
  facebook: '',  // TODO
};

export type SiteConfig = typeof site;
