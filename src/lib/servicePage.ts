/** Research-informed copy. Prices and included time come from the service catalogue. */
export interface ServicePageContent {
  slug: string;
  serviceId: string;
  title: string;
  description: string;
  eyebrow: string;
  heading: string;
  intro: string;
  fitHeading: string;
  situations: { title: string; body: string }[];
  sessionHeading: string;
  sessionSteps: { title: string; body: string }[];
  deliverable: { title: string; intro: string; items: string[]; note: string };
  boundaries: string[];
  faqs: { q: string; a: string }[];
  related: { slug: string; label: string }[];
  resourceLinks?: { title: string; url: string; description: string }[];
  secondaryOfferId?: string;
}
