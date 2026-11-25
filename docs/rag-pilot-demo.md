# Piloto RAG original de NébulaIA

Este piloto no es una fuente institucional. Su único propósito es validar el
flujo técnico de ingestión sin copiar reglamentos, mallas, asignaturas, créditos,
requisitos o datos personales de la UNAB.

## Archivos controlados

- Documento: `docs/rag-pilot/nebula-rag-demo.html`.
- Evidencia: `docs/rag-pilot/authorization.json`.
- Configuración: `config/rag-demo-pilot.json`.
- URL local reservada: `https://demo.nebula.invalid/rag/nebula-rag-demo.html`.

El dominio `.invalid` es deliberadamente no resoluble y solo identifica el
preview local. No debe almacenarse en Supabase como URL de producción. Antes de
un staging remoto, el archivo aprobado e inalterado debe publicarse en un host
HTTPS controlado por el equipo; luego deben actualizarse la URL y la allowlist.

## Preview local autorizado por la tarea

```powershell
$env:PYTHONIOENCODING = 'utf-8'
python -m nebula_rag.cli preview `
  --sources .\config\rag-demo-pilot.json `
  --source nebula_original_demo `
  --url https://demo.nebula.invalid/rag/nebula-rag-demo.html
Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
```

El preview no usa red, PostgreSQL ni Gemini. Con autorización `pending`, el
comando `stage` falla antes de abrir una conexión de base de datos.

## Aprobación interna requerida

Antes de staging, una persona autorizada del equipo debe revisar el documento y
cambiar de forma coherente la evidencia y la configuración:

- `status` / `authorization_status`: `approved`;
- `authorized_by`: identidad real del aprobador;
- `authorization_date`: fecha ISO;
- usos permitidos: `extract`, `chunk`, `embed`, `store`, `present`;
- URL HTTPS canónica y host controlado;
- hash del documento sin cambios respecto del contenido revisado.

La aprobación autoriza el tratamiento técnico del material propio; no lo
convierte en contenido oficial, normativo, curricular o personal.

## Protección de recuperación

La migración 011 agrega `content_class` y evidencia de autorización. Sus dos RPC
productivas filtran `content_class='institutional'`, por lo que un documento
`demo_non_institutional` nunca puede aparecer en respuestas normales, incluso
si fue aprobado y tiene embeddings. El piloto valida ingestión, embeddings,
revisión y exclusión; no valida una respuesta académica del agente.

## Orden remoto posterior

1. Revisar y aplicar 011 en una ventana controlada.
2. Verificar que las RPC conservan propietario, `SECURITY DEFINER`, `search_path`
   vacío y permisos exclusivos de `nebula_rag_api`.
3. Publicar el documento aprobado en HTTPS controlado.
4. Repetir preview y comparar hash, clasificación y cantidad de fragmentos.
5. Ejecutar stage con `nebula_rag_ingest_login`.
6. Verificar la fila `pending` y sus metadatos, sin mostrar el contenido.
7. Autorizar explícitamente las llamadas Gemini por fragmento y ejecutar embed.
8. Revisar fragmentos, perfil, dimensión, localizadores y evidencia con el login
   revisor.
9. Aprobar o rechazar. Mantener el perfil de embeddings inactivo.
10. Confirmar que ambas RPC productivas excluyen el documento demo.

No debe activarse el perfil ni conectarse n8n como parte de este piloto.
