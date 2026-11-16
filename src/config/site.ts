// ============================================================================
// SITE CONFIG — single source of truth for brand + contact info.
// Edit this file to rebrand or update contact details. Nothing else needs to
// change. All placeholder values are clearly marked with TODO.
// ============================================================================

export const site = {
  // --- Brand ---
  brandName: 'Sleepy Llamas',
  tagline: 'Practical guidance for your whole family.',
  shortDescription:
    'Family and newborn consultations, home visits, and nanny coaching with Catalina Llamas. Based in Queens, with phone and video support for parents and caregivers.',

  // --- Contact (TODO: replace with real values) ---
  email: 'sleepyllamasdoula@gmail.com',
  phone: '',                           // Add verified business number to display.
  phoneHref: '',
  serviceArea: 'Queens and nearby NYC neighborhoods',
  responseTime: 'within two business days',
  whatsapp: '',                        // Add verified WhatsApp number to display.
  whatsappDisplay: '',

  // --- Payment handles (shown AFTER consultation — informational only) ---
  venmoHandle: '',                     // Add verified business handle to display.
  zelleHandle: 'sleepyllamasdoula@gmail.com', // TODO — update if using a different Zelle email
  stripePaymentLink: '',                // TODO — paste a Stripe Payment Link URL when ready

  // --- Social (optional, leave empty strings to hide) ---
  instagram: '', // TODO e.g. 'https://instagram.com/sleepyllamas'
  facebook: '',  // TODO
};

export type SiteConfig = typeof site;
