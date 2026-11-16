import type { APIRoute } from 'astro';
import { servicePages, withBase } from '../config/serviceRoutes';

export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error('Configure the public Astro site URL before generating a sitemap.');
  const baseUrl = new URL(withBase(''), site).href;
  const paths = ['', ...servicePages.map((page) => `${page.slug}/`), 'resume/', 'privacy/'];
  const urls = paths.map((path) => `<url><loc>${new URL(path, baseUrl).href.replace(/&/g, '&amp;')}</loc></url>`).join('');
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
};
