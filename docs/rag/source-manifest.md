# Manifiesto de fuentes para RAG — NébulaIA 2.0

Inventario **de solo referencia** de documentos e información universitaria
recuperados del proyecto anterior (`C:\Users\angil\OneDrive\Desktop\nebula`).

> ⚠️ **No se ha importado nada todavía.** No se reutilizan embeddings, código RAG,
> workflows ni bases de datos del proyecto anterior. Los archivos originales
> permanecen en su carpeta; aquí solo se catalogan sus referencias. El procesamiento
> (extracción → chunk → embed → almacenamiento) queda **pendiente de autorización**
> y de verificación de vigencia por documento.

Fecha del inventario: 2026-11-25. Alcance curricular: Ingeniería de Sistemas UNAB,
plan histórico de 9 semestres y 151 créditos.

| # | Título | Fuente oficial | URL | Fecha doc. | Vigencia | Alcance académico | Ruta local (proyecto anterior) | Autorización proc. | Tema |
|---|--------|----------------|-----|------------|----------|-------------------|-------------------------------|--------------------|------|
| SRC-04 | Reglamento Estudiantil de Pregrado | UNAB | https://unab.edu.co/wp-content/uploads/2026/04/Reglamento-estudiantil-pregrado.pdf | 2019 (archivo 2026-04) | Oficial; sin reemplazo posterior hallado (verificado 2026-11-10) | Institucional pregrado | `_local_rag_documents/SRC-04_reglamento_estudiantil_pregrado.pdf` | Pendiente | Reglamento estudiantil · Sistema de notas · Requisitos de grado |
| SRC-07 | Acuerdo de acreditación CNA N.º 035 de 2022 | Consejo Nacional de Acreditación (CNA) | https://www.cna.gov.co/1779/articles-401786_No_35_2022.pdf | 2022 | Histórica (verificada) | Contexto del plan antiguo de 9 semestres | `_local_rag_documents/SRC-07_acreditacion_CNA_035_2022.pdf` | Pendiente | Normas institucionales · Acreditación |
| SRC-08 | Reconocimientos — Esquema de Movilidad Educativa | UNAB | https://unab.edu.co/wp-content/uploads/2022/10/Reconocimientos-Esquema-Movilidad-Educativa.pdf | 2022 | Histórica (verificada) | Contexto del plan antiguo | `_local_rag_documents/SRC-08_movilidad_educativa.pdf` | Pendiente | Matrícula y procedimientos · Reconocimiento de créditos |
| SRC-25 | Guía de cátedra — Internet de las Cosas (TELE18052) | UNAB | https://servicios.unab.edu.co/Archivos/?p=GuiasDeCatedra%2FTELE18052.pdf | 2023 | Documentada (pendiente de confirmar vigencia actual) | Cohorte pendiente, plan antiguo | `_local_rag_documents/SRC-25_guia_internet_cosas_TELE18052.pdf` | Pendiente | Prerrequisitos · Guía de curso |
| SRC-26 | Guía de cátedra — Estructura de Datos (COMP18037) | UNAB | https://servicios.unab.edu.co/Archivos/?p=GuiasDeCatedra%2FCOMP18037.pdf | 2022 | Documentada (pendiente) | Contexto del plan antiguo | `_local_rag_documents/SRC-26_guia_estructura_datos_COMP18037.pdf` | Pendiente | Prerrequisitos · Guía de curso |
| SRC-27 | Guía de cátedra — Ética (FILO18001) | UNAB | https://servicios.unab.edu.co/Archivos/?p=GuiasDeCatedra%2FFILO18001.pdf | 2022 | Documentada (pendiente) | Contexto del plan antiguo | `_local_rag_documents/SRC-27_guia_etica_FILO18001.pdf` | Pendiente | Identidad de curso · Guía de curso |
| CAL-2026-2 | Calendario académico 2026-2 | UNAB | https://www.unab.edu.co/es/estudiantes/calendario-academico | Verificado 2026-11-22 | Periodo 2026-2 (verificada a esa fecha) | Calendario institucional | `nebula_calendario_2026_2.csv` | Pendiente | Calendario académico · Fechas de matrícula |
| SRC-11 | Matrícula Pregrado Profesional (procedimiento) | UNAB | https://unab.edu.co/matricula-pregrado-profesional/ | s. f. (consultado 2026-11-06) | Contextual (pendiente) | Procedimientos de inscripción | — (sin archivo local; solo referencia web) | Pendiente | Matrícula y procedimientos |

## Temas solicitados y cobertura

- **Reglamento estudiantil** → SRC-04.
- **Sistema de notas** → SRC-04 (capítulo de evaluación; verificar artículos antes de usar).
- **Calendario académico** → CAL-2026-2.
- **Matrícula y procedimientos** → SRC-11, SRC-08, CAL-2026-2 (fechas).
- **Requisitos de grado** → SRC-04 (verificar artículos aplicables al plan antiguo).
- **Otras normas institucionales** → SRC-07 (acreditación), SRC-08 (movilidad).

## Siguientes pasos (no ejecutados)

1. Confirmar vigencia y términos de reuso de cada documento antes de procesarlo.
2. Marcar la autorización de procesamiento por documento (hoy todas en *Pendiente*).
3. Solo entonces: extracción → chunking → embeddings con el pipeline NUEVO de este
   repositorio (sin reutilizar el RAG antiguo). Mientras tanto, `RAG_ENABLED=false`.

> Las referencias oficiales (URLs, fechas, códigos) provienen del inventario del
> proyecto anterior (`rag/phase42_sources.json`, `docs/fase3/inventario_fuentes.md`,
> `nebula_calendario_2026_2.csv`) y de la migración académica ya validada en este
> repositorio. No constituyen una verificación nueva: la vigencia marcada como
> "pendiente" debe confirmarse antes de cualquier procesamiento.
