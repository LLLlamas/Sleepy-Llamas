import { consultingServices } from '../config/services';
import { servicePagePath } from '../config/serviceRoutes';
import { site } from '../config/site';

export function serializeJsonLd(value: unknown): string {
  return JSON.stringify(value).replace(/</g, '\u003c');
}

export function buildSiteGraph(options: {
  baseUrl: string;
  canonicalUrl: string;
  title: string;
  description: string;
  mainEntityId?: string;
  extraNodes?: Record<string, unknown>[];
}) {
  const { baseUrl, canonicalUrl, title, description, extraNodes = [] } = options;
  const organizationId = `${baseUrl}#organization`;
  const personId = `${baseUrl}#catalina`;
  const serviceNodes = consultingServices.map((service) => {
    const path = servicePagePath(service.id);
    const serviceUrl = path ? new URL(path, baseUrl).href : `${baseUrl}#services`;
    const serviceId = path && service.id !== 'first-weeks-plan'
      ? `${serviceUrl}#service` : `${baseUrl}#service-${service.id}`;
    return {
      '@type': 'Service', '@id': serviceId,
      name: service.title, serviceType: service.title, description: service.description,
      url: serviceUrl, provider: { '@id': organizationId },
      areaServed: { '@type': 'Place', name: site.serviceArea },
      offers: { '@type': 'Offer', url: `${serviceUrl.split('#')[0]}#contact`,
        description: `Starting rate for ${service.duration}; final scope and price confirmed before booking.`,
        priceSpecification: { '@type': 'PriceSpecification', minPrice: service.price, priceCurrency: 'USD' } },
    };
  });
  const nodes: Record<string, unknown>[] = [
    { '@type': 'Organization', '@id': organizationId, name: site.brandName,
      url: baseUrl, description: site.shortDescription, email: site.email,
      founder: { '@id': personId }, ...(site.phone ? { telephone: site.phone } : {}),
      hasOfferCatalog: { '@type': 'OfferCatalog', name: 'Family consulting and caregiver support',
        itemListElement: serviceNodes.map((service) => ({ ...service.offers,
          name: service.name, itemOffered: { '@id': service['@id'] } })) } },
    { '@type': 'Person', '@id': personId, name: 'Catalina Llamas',
      jobTitle: 'Family consultant and certified postpartum doula',
      url: new URL('resume/', baseUrl).href, knowsLanguage: ['English', 'Spanish'],
      worksFor: { '@id': organizationId } },
    { '@type': 'WebSite', '@id': `${baseUrl}#website`, url: baseUrl,
      name: site.brandName, publisher: { '@id': organizationId }, inLanguage: 'en-US' },
    { '@type': 'WebPage', '@id': `${canonicalUrl}#webpage`, url: canonicalUrl,
      name: title, description, inLanguage: 'en-US',
      isPartOf: { '@id': `${baseUrl}#website` },
      mainEntity: { '@id': options.mainEntityId ?? organizationId } },
    ...serviceNodes, ...extraNodes,
  ];
  // A service page can refine its own node while keeping one stable identity.
  const unique = new Map<string, Record<string, unknown>>();
  nodes.forEach((node, index) => unique.set(String(node['@id'] ?? index), node));
  return { '@context': 'https://schema.org', '@graph': [...unique.values()] };
}
