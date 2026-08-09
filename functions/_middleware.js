export async function onRequest(context) {
  const { request, next } = context;

  const accept = request.headers.get('Accept') || '';

  if (accept.includes('text/markdown')) {
    const url = new URL(request.url);
    let path = url.pathname;

    if (path.endsWith('/')) {
      path = path + 'index.md';
    } else if (path.endsWith('.html')) {
      path = path.replace(/\.html$/, '/index.md');
    } else if (!path.endsWith('.md')) {
      path = path + '/index.md';
    }

    const mdUrl = new URL(path, url.origin);
    const mdRequest = new Request(mdUrl.toString(), request);

    const response = await fetch(mdRequest);

    if (response.ok) {
      let body = await response.text();

      body = body.replace(/<no value>/g, '');
      body = body.replace(/\{\{<[^>]*>\}\}/g, '');
      body = body.replace(/\n{3,}/g, '\n\n');

      const mdResponse = new Response(body, {
        status: 200,
        headers: {
          'Content-Type': 'text/markdown; charset=utf-8',
          'Vary': 'Accept',
          'Cache-Control': 'public, max-age=3600',
        },
      });

      return mdResponse;
    }

    return next();
  }

  return next();
}