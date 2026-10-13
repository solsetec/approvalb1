# Migración del sitio a Cloudflare Pages

## Contexto
El sitio (HTML estático, sin build) hoy se publica con GitHub Pages en `solsetec.approvalb1.com`. No hay workflow propio en `.github/`: es el despliegue automático de Pages. Motivos para migrar:
- Los términos de GitHub Pages no contemplan uso comercial.
- GitHub Pages no tiene SLA.
- No permite headers HTTP propios.

Objetivo: servir el mismo repo desde Cloudflare Pages, con headers de seguridad, y dejar GitHub Pages como espejo en `solsetec.github.io/approvalb1`.

Decisiones del usuario:
- El DNS de `approvalb1.com` está en **otro proveedor**, no en Cloudflare.
- GitHub Pages queda **como espejo**.
- El repo sigue **público**.

## Cambios en el repo

### 1. Nuevo `_headers` (raíz)
Jekyll de GitHub Pages ignora los archivos que empiezan con `_`, así que no afecta al espejo. Cloudflare redirige `/x.html` → `/x` con un 308 ("pretty URLs"), así que cada regla cubre las dos rutas.

- `/*` (todo el sitio): `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` (el token va en la query), `Permissions-Policy: camera=(), microphone=(), geolocation=()`, `Strict-Transport-Security: max-age=31536000` (sin `includeSubDomains`).
- CSP según el tipo de página. Todas incluyen `'unsafe-inline'`, porque todo el JS y el CSS son inline y hay handlers `onsubmit`/`onclick`. El valor real está en `connect-src` y `frame-ancestors`:
  - `/test/*`, `/prod/*`: `default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src https://approvalb1-supabase.scalifa.cloud https://apb1-b.solsetec.com.co; base-uri 'none'; frame-ancestors 'none'`
  - `/comments`, `/comments.html`: igual, pero con `connect-src https://webhook-solsetec.tangara.cloud https://apb1-b.solsetec.com.co`.
  - Páginas de resultado (`/approved*`, `/rejected*`, `/reused*`, `/invalidtoken*`, `/invalidcomment*`; no tienen script): `default-src 'none'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; frame-ancestors 'none'`
  - `/Index.HTML` (Mini App de Telegram): `script-src 'unsafe-inline' https://telegram.org; connect-src https://webhook-solsetec.tangara.cloud https://apb1-b.solsetec.com.co; frame-ancestors https://web.telegram.org https://*.telegram.org` (Telegram Web la abre dentro de un iframe), además de los `style`/`img` de arriba.
  - `/dev/*` **no lleva CSP**: DEV no está soportado y no se toca (CLAUDE.md).

### 2. `CNAME`
Se elimina **después** del corte de DNS (paso 5). Si se queda, GitHub Pages redirige `github.io` al dominio y el espejo no funciona.

### 3. Documentación
- `CLAUDE.md`, sección Overview: despliegue en Cloudflare Pages, GitHub Pages como espejo en `solsetec.github.io/approvalb1`, y el `_headers` con las CSP por página (una página nueva que llame a otro host necesita su `connect-src`).
- Nota de memoria `project_webhook_failover.md` / memoria nueva de hosting.

## Pasos manuales en los paneles (te los dejo como checklist)
1. **Cloudflare** → Workers & Pages → Create → Pages → Connect to Git → `solsetec/approvalb1`. Rama de producción `main`, framework preset *None*, build command vacío, output directory `/`.
2. Probar en `<proyecto>.pages.dev` (ver Verificación).
3. En el proveedor DNS: bajar el TTL del registro `solsetec` a 300 s y revisar que no haya registros **CAA** en `approvalb1.com` que bloqueen las CA de Cloudflare (Let's Encrypt / Google Trust Services / SSL.com).
4. En Cloudflare Pages → Custom domains → agregar `solsetec.approvalb1.com` **primero**. Después, en el proveedor DNS, cambiar el CNAME `solsetec` de `solsetec.github.io` a `<proyecto>.pages.dev`. Esperar a que el estado quede *Active* (certificado emitido).
5. Ya validado: commit que elimina `CNAME`, y en GitHub → Settings → Pages, borrar el custom domain. El espejo queda en `https://solsetec.github.io/approvalb1/...`.

**Rollback:** devolver el CNAME del DNS a `solsetec.github.io` y volver a poner el custom domain (y el archivo `CNAME`) en GitHub Pages.

## Riesgos a validar en `pages.dev` antes del corte
- **Pretty URLs:** confirmar que el 308 `/prod/p_main.html?token=…` → `/prod/p_main?token=…` conserva la query string. Los enlaces de los correos dependen de esto.
- **`Index.HTML` con extensión en mayúsculas:** confirmar que se sirve con `Content-Type: text/html`. Si no, agregar `Content-Type: text/html; charset=utf-8` en su regla de `_headers`.
- Que las reglas de `_headers` apliquen tanto a la ruta `.html` como a la ruta "bonita".

## Verificación
1. `curl -sI https://<proyecto>.pages.dev/prod/p_main.html?token=x&decision_inicial=approved&prf=solsetec`: 308 con la query intacta. Luego `curl -sI` a la URL final: headers y CSP presentes. Repetir con `/Index.HTML`, `/comments.html`, `/approved.html` y `/dev/d_main.html` (este sin CSP).
2. En el navegador, en `pages.dev`:
   - `/prod/p_main.html` con un token falso → vista "Enlace inválido". El relay responde `invalidtoken`, lo que prueba CORS y `connect-src`.
   - Con `rcm=both` → aparece el formulario, la fuente Inter carga y la consola no muestra violaciones de CSP.
   - Lo mismo en `/test/t_main.html`.
3. Después del DNS: `curl -sI https://solsetec.approvalb1.com/prod/p_main.html` muestra `server: cloudflare`. Hacer una aprobación real de TEST de punta a punta y revisar en los logs del `decision-relay` el evento `decision_delivered`.
4. Abrir la Mini App de Telegram en el móvil y en Telegram Web (`frame-ancestors`) y descargar un PDF.
5. Confirmar que el espejo `solsetec.github.io/approvalb1/prod/p_main.html` carga sin redirigir.
