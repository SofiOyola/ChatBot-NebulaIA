# Nébula RAG y recopilación académica

## Estado verificable

La solución local contiene extracción, fragmentación, ciclo de revisión,
adaptadores de embeddings, persistencia PostgreSQL y un contrato HTTP para n8n.
No contiene fuentes UNAB activas ni documentos académicos. No se ha desplegado
en Supabase ni conectado al workflow principal.

La auditoría de candidatas institucionales está en
[`rag-source-audit-2026-11-25.md`](rag-source-audit-2026-11-25.md). Todas siguen
deshabilitadas: robots.txt no equivale a autorización de reutilización.

## Flujo y límites de confianza

```text
fuente HTTPS allowlisted
  -> robots.txt + límite de frecuencia/tamaño/redirección
  -> extractor HTML/PDF
  -> hash SHA-256 + fragmentación determinista
  -> stage (pending; la revisión anterior deja de ser current)
  -> embeddings del mismo perfil/dimensión
  -> revisión humana
  -> approve (documented + current)
  -> RPC SECURITY DEFINER
  -> API privada de herramienta
  -> n8n
```

El texto recuperado siempre se etiqueta como datos no confiables. Las posibles
instrucciones incrustadas se marcan con `possible_prompt_injection`, se delimitan
como `<reference>` y nunca deben convertirse en mensajes system/developer.

## Modelo seleccionado, pendiente de activación

Para texto académico se propone `gemini-embedding-001` con dimensión 768:

- Google lo mantiene disponible para texto y documenta los tipos
  `RETRIEVAL_DOCUMENT` y `RETRIEVAL_QUERY`.
- Google recomienda 768, 1536 o 3072 dimensiones.
- 768 reduce almacenamiento y costo de comparación.
- Google exige normalización manual para dimensiones distintas de 3072; el
  adaptador valida dimensión, valores finitos y norma, y normaliza el resultado.

Fuente técnica revisada el 25 de noviembre de 2026:
<https://ai.google.dev/gemini-api/docs/embeddings>.

La activación requiere aceptar costos, términos y tratamiento de los documentos.
Cambiar modelo o dimensión exige un perfil nuevo y reindexación; nunca se mezclan
vectores de perfiles distintos.

## Fuentes y scraper

`config/rag-sources.example.json` contiene candidatas deshabilitadas. Antes de
habilitar una fuente UNAB se debe registrar:

1. URL pública y propietario institucional;
2. host exacto y redirecciones esperadas;
3. revisión de `robots.txt` y términos de uso;
4. tipos de contenido autorizados;
5. frecuencia aprobada y contacto operativo;
6. licencia/vigencia y responsable de validación.

No se evaden autenticación, CAPTCHA, bloqueos ni restricciones. Un fallo al
verificar robots impide la descarga. HTML elimina navegación y scripts; PDF sin
texto requiere OCR y revisión fuera de este proceso.

## Ciclo de vida

- Hash repetido: no crea otra revisión.
- Hash nuevo para la misma URL: crea `pending`, enlaza `supersedes_document_id`
  y retira inmediatamente la versión anterior de resultados.
- `approve`: fija una única revisión `documented + current`.
- `reject`: fija `excluded + not current`.
- Solo `documented + current` participa en búsqueda.

La recuperación también exige `validity_status = current`. Autoridad, tipo de
información y alcance curricular son columnas verificadas. La RPC pública solo
acepta `old_9s_151c` o `general`; el plan `new_2027_8s_134c` no es recuperable
por la herramienta de Nébula.

La búsqueda híbrida pondera 75 % similitud coseno, hasta 20 % coincidencia
léxica y una bonificación de autoridad limitada a 5 %. Esto ayuda con artículos,
fechas y nombres exactos sin convertir una noticia en norma.

Esta política prefiere una ausencia temporal de resultados antes que servir una
versión posiblemente obsoleta. Restaurar una revisión anterior también requiere
aprobación explícita.

## Ejecución manual del scraper

Primero copie el ejemplo y agregue únicamente fuentes ya revisadas:

```powershell
python -m pip install -e .
Copy-Item .\config\rag-sources.example.json .\config\rag-sources.json
python -m nebula_rag.cli preview --sources .\config\rag-sources.json --source NOMBRE --url URL_PUBLICA
python -m nebula_rag.cli stage --sources .\config\rag-sources.json --source NOMBRE --url URL_PUBLICA
```

Después de inspeccionar el documento pendiente, la generación y aprobación son
acciones separadas:

```powershell
python -m nebula_rag.cli embed --document-id 123
python -m nebula_rag.cli approve --document-id 123
```

Para rechazarlo:

```powershell
python -m nebula_rag.cli reject --document-id 123
```

Los secretos solo se proporcionan al proceso mediante variables de entorno. El
archivo real `config/rag-sources.json` no debe contener secretos.

## Automatización futura

n8n puede programar el comando de staging o llamar a un servicio equivalente,
pero no debe aprobar documentos automáticamente. Los eventos deben registrar
solo URL, hash, estado técnico, fecha y conteos; nunca claves o cuerpos completos.
Los reintentos ya están limitados y la revisión humana permanece obligatoria.

## Estimación inicial

Con fragmentos de hasta 1.800 caracteres, un piloto de 3–5 documentos cortos se
estima en 10–40 fragmentos. El adaptador actual hace una llamada por fragmento:
máximo 40 llamadas de indexación y 2–3 consultas de validación. `preview` debe
calcular el número real antes de autorizar costo. La tarifa publicada al
25 de noviembre de 2026 para `gemini-embedding-001` es USD 0,15 por millón de
tokens estándar y USD 0,075 en batch; cuotas y precios deben revalidarse en el
proyecto de AI Studio antes de activar.
