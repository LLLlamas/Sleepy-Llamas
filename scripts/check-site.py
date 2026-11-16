"""Check the built commercial site, its link graph, metadata and service forms."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1] / 'dist'

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.graphs, self.metas = set(), [], [], {}
        self.canonical, self.h1_count, self.json_buffer, self.in_json = '', 0, '', False
        self.selected, self.select_name = {}, ''
    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get('id'):
            assert attrs['id'] not in self.ids, f'Duplicate id: {attrs["id"]}'
            self.ids.add(attrs['id'])
        if tag == 'h1': self.h1_count += 1
        if tag == 'a' and attrs.get('href'): self.links.append(attrs['href'])
        if tag == 'link' and attrs.get('rel') == 'canonical': self.canonical = attrs['href']
        if tag == 'meta': self.metas[attrs.get('name', attrs.get('property'))] = attrs.get('content', '')
        if tag == 'script' and attrs.get('type') == 'application/ld+json': self.in_json, self.json_buffer = True, ''
        if tag == 'select': self.select_name = attrs.get('name', '')
        if tag == 'option' and 'selected' in attrs: self.selected[self.select_name] = attrs.get('value', '')
    def handle_data(self, data):
        if self.in_json: self.json_buffer += data
    def handle_endtag(self, tag):
        if tag == 'script' and self.in_json:
            self.graphs.append(json.loads(self.json_buffer)); self.in_json = False
        if tag == 'select': self.select_name = ''

pages = {}
for file in root.rglob('*.html'):
    # Moonlog is built separately by the Pages workflow, outside this site audit.
    if 'Moonlog' in file.relative_to(root).parts: continue
    page = Page(); page.feed(file.read_text()); pages[file.resolve()] = page
assert len(pages) == 6, f'Expected six public site pages, found {len(pages)}. Build first.'
base = pages[(root / 'index.html').resolve()].canonical
base_path, host = urlsplit(base).path, urlsplit(base).netloc
for file, page in pages.items():
    assert page.h1_count == 1, f'{file}: one clear H1 required'
    assert 'main-content' in page.ids, f'{file}: missing skip-link target'
    relative = file.parent.relative_to(root.resolve()).as_posix()
    expected = base if relative == '.' else f'{base}{relative}/'
    assert page.canonical == expected, f'{file}: wrong canonical {page.canonical}'
    assert page.metas.get('description'), f'{file}: missing description'
    assert page.metas.get('og:url') == expected, f'{file}: inconsistent social URL'
    assert 'social-card.png' in page.metas.get('og:image', ''), f'{file}: missing share image'
    nodes = page.graphs[0]['@graph']
    node_ids = [node.get('@id') for node in nodes]
    assert len(node_ids) == len(set(node_ids)), f'{file}: duplicate structured-data identities'
    assert not any(node.get('@type') in ('FAQPage', 'ProfessionalService') for node in nodes), f'{file}: obsolete markup'
    assert any(node.get('@type') == 'Organization' for node in nodes), f'{file}: missing organization'
    for href in page.links:
        link = urlsplit(href)
        if link.scheme in ('mailto', 'tel') or (link.netloc and link.netloc != host): continue
        if link.path.startswith(base_path):
            path = unquote(link.path[len(base_path):])
            if path.startswith('Moonlog/'): continue
            target = root / path
            if not path or link.path.endswith('/'): target /= 'index.html'
            target = target.resolve()
        elif not link.path: target = file
        else: continue
        assert target.exists(), f'{file}: broken local link {href}'
        if link.fragment and target in pages: assert link.fragment in pages[target].ids, f'{file}: missing anchor {href}'

services = {
    'newborn-postpartum-consultations': ('newborn-postpartum-consult', 'not-sure', 250),
    'nanny-caregiver-coaching': ('caregiver-training', 'in-person', 595),
    'first-days-home-visit': ('home-consult', 'in-person', 550),
}
descriptions = set()
for slug, (service_id, contact_format, price) in services.items():
    page = pages[(root / slug / 'index.html').resolve()]
    assert page.selected.get('service') == service_id, f'{slug}: form service not preselected'
    assert page.selected.get('format') == contact_format, f'{slug}: wrong appointment format'
    assert page.metas['description'] not in descriptions, 'Service descriptions must be distinct'
    descriptions.add(page.metas['description'])
    node = next(node for node in page.graphs[0]['@graph'] if node.get('@id') == f'{page.canonical}#service')
    assert node['offers']['priceSpecification']['minPrice'] == price, f'{slug}: wrong approved price'

xml = ET.parse(root / 'sitemap.xml')
urls = {loc.text for loc in xml.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')}
assert urls == {page.canonical for page in pages.values()}, 'Sitemap and public pages disagree'
assert (root / 'social-card.png').is_file(), 'Missing social-card asset'
print('PASS: six pages; canonical URLs, internal links, sitemap, structured data, approved rates and preselected inquiry forms.')
