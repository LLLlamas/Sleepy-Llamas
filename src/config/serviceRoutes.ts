export const servicePages = [
  { serviceId: 'newborn-postpartum-consult', slug: 'newborn-postpartum-consultations', label: 'Newborn & postpartum consultations' },
  { serviceId: 'caregiver-training', slug: 'nanny-caregiver-coaching', label: 'Nanny & caregiver coaching' },
  { serviceId: 'home-consult', slug: 'first-days-home-visit', label: 'First days home visits' },
] as const;

export function servicePagePath(serviceId: string): string | undefined {
  if (serviceId === 'first-weeks-plan') return 'newborn-postpartum-consultations/#support-options';
  const page = servicePages.find((candidate) => candidate.serviceId === serviceId);
  return page ? `${page.slug}/` : undefined;
}

export function withBase(path = '', base = import.meta.env.BASE_URL): string {
  return `${base.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
}
