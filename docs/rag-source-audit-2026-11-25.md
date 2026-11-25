# Auditoría puntual de fuentes UNAB — 2026-11-25

Esta revisión comprobó páginas individuales y `robots.txt`; no ejecutó crawler,
scraper ni descarga masiva. Accesibilidad pública no equivale a permiso de
reutilización. No se encontró una autorización general inequívoca para copiar e
indexar contenidos, por lo cual todas las fuentes permanecen deshabilitadas.

`https://unab.edu.co/robots.txt` permite rutas públicas y bloquea `/wp-admin/`,
salvo `admin-ajax.php`; también publica un sitemap. Esto no constituye licencia.

| Fuente | Acceso observado | Clasificación y aplicabilidad | Decisión |
|---|---|---|---|
| Sistema de Bibliotecas | Pública; enlaza repositorio, catálogo y terceros | Bibliotecas; institucional informativa; general | Manual/pendiente. No seguir recursos licenciados |
| Noticias | Índice público con categorías y fechas | Noticias/eventos; alcance por artículo | Sin crawling. Aprobar URL, categoría, fecha y relevancia individualmente |
| Intranet | Ruta `usuarioInvalido`; HEAD crea cookie de sesión | Protegida/no comprobada | Excluida; requiere autorización y versión pública |
| Noticia Reglamento 2019 | Pública, publicada 2019-11-12 | Informativa; general de pregrado | No sustituye el PDF normativo |
| Reglamento PDF | Resolución 564, promulgada 2019-11-29; Acuerdo 105 de 2019 | Institucional normativa; general de pregrado | Revisión jurídica y permiso de indexación pendientes |
| Programa Ingeniería de Sistemas | Pública; vigencia 2027 y 8 semestres | Currículo; `new_2027_8s_134c` | Excluida del plan antiguo |
| Noticia de nueva malla | Pública, 2026-10-16; anuncia 2027, 8 semestres y 134 créditos | Currículo/noticia; `new_2027_8s_134c` | Excluida del plan antiguo |

No se consultaron bases licenciadas, catálogos de terceros, MiPortalU ni recursos
con sesión. El aviso de privacidad no es una licencia de reproducción.

## Regla curricular

El catálogo estructurado de 9 semestres, 51 posiciones y 151 créditos es la
fuente primaria. Los documentos de 2027 pueden conservarse para auditoría con
alcance `new_2027_8s_134c`, pero la RPC pública rechaza ese alcance y nunca los
devuelve al consultar `old_9s_151c`.

No se crean equivalencias entre planes. Un documento mixto se divide solo si un
revisor puede clasificar cada fragmento; de lo contrario queda `unknown` y fuera
de la recuperación del plan antiguo.
