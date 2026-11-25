# Regresion del webhook n8n

El runner ejecuta exactamente un caso por proceso y valida tanto el codigo HTTP como un subconjunto obligatorio del JSON. Usa `HttpWebRequest`, no `curl.exe`, y codifica el cuerpo como UTF-8 sin BOM. No guarda el cuerpo completo ni encabezados de la respuesta en el reporte.

## Simulacion local sin Internet

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaN8nRegressionRunner.ps1
```

La simulacion comprueba T01-T06 como PASS, T07-T08 como SKIP y dos controles negativos: codigo HTTP incorrecto y JSON incorrecto deben ser detectados como FAIL.

## Solicitud real, una por vez

Antes de cada caso, abra el workflow privado en n8n Cloud y pulse **Execute workflow**. No importe ni publique respaldos. Después ejecute el caso; el runner pedira escribir `EJECUTAR` antes de enviar una sola solicitud.

Comando exacto para T01:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaN8nRegression.ps1 -CaseId T01 -Transport Real -AllowNetwork
```

Cambie únicamente `T01` por `T02` ... `T06`. Para automatizacion controlada puede reemplazar la confirmacion interactiva por `-ConfirmedWorkflowListening`, siempre despues de activar manualmente Execute workflow.

T07 se ejecuta mediante un runner independiente que obtiene el token en memoria; consulte la seccion siguiente. T08 permanece en SKIP hasta contar con un token de prueba alterado o vencido. En T06, un PASS automatizado solo demuestra la respuesta 401 con el JSON esperado: el reporte conserva como pendiente la evidencia manual de que el flujo alcanzo la validacion de Supabase.

## T07: autenticacion estudiantil real

Primero puede validar toda la logica sin Internet ni credenciales:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT07Offline.ps1
```

Para la prueba real, use el comando siguiente. El script solicita interactivamente correo, contrasena y clave publica `publishable` o `anon`; ninguna se recibe como parametro. Tras autenticar, espera a que active manualmente **Execute workflow** y confirme escribiendo `EJECUTAR`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT07.ps1 -Transport Real -AllowNetwork
```

El token solo permanece en memoria. El reporte de T07 contiene exclusivamente estados HTTP, validez JSON, resultado, diagnostico seguro y fecha. Un PASS demuestra solamente acceso autenticado y respuesta provisional HTTP 200 con JSON valido; no demuestra que el chatbot completo funcione.

## T08: JWT con firma alterada

T08 inicia sesion igual que T07 y cambia determinísticamente un solo caracter del segmento de firma, conservando sin cambios el header y el payload. Valide primero la logica offline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT08Offline.ps1
```

Ejecucion real interactiva:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT08.ps1 -Transport Real -AllowNetwork
```

El resultado automatizado exige HTTP 401, JSON valido y `error: unauthorized`. Aun cuando esas aserciones pasen, el reporte mantiene como `PENDING` la evidencia manual de que el recorrido de n8n alcanzo la validacion de Supabase. No se guardan el JWT original, el alterado, el refresh token, las credenciales, el header Authorization ni la respuesta completa.

## T09: evaluacion academica del agente

El runner ejecuta un solo escenario (`T09-A`, `T09-B` o `T09-C`) y separa el contrato automatico de la evaluacion humana. Pruebas offline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT09Offline.ps1
```

Ejemplo real para T09-A:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT09.ps1 -Scenario T09-A -Transport Real -AllowNetwork
```

Cambie solo el escenario para ejecutar T09-B o T09-C. El runner exige HTTP 200, JSON valido, `success` booleano `true`, `project` igual a `Nebula 2.0` y `response` textual no vacia y significativa. Muestra el texto exclusivamente en la terminal y no lo incorpora al reporte. Las secuencias de escape literales sospechosas se advierten sin modificar el texto.

Un `automaticStatus: PASS` significa unicamente que el transporte y la estructura son validos. `manualEvaluation` permanece siempre en `PENDING`: una persona debe valorar exactitud, claridad, amabilidad y, para T09-C, que el agente no invente informacion personal o curricular.

T07 y T09 generan ahora un `conversationId` efimero que cumple `^[A-Za-z0-9_-]{8,64}$` y lo incluyen en el JSON enviado. El valor no se muestra ni se guarda; sus autocontroles solo registran si el formato es valido. T01-T06 y T08 no cambian.

## T10: memoria conversacional e aislamiento

Ejecute primero las simulaciones sin red:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT10Offline.ps1
```

Comandos reales, uno por escenario:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT10.ps1 -Scenario T10-A -Transport Real -AllowNetwork
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT10.ps1 -Scenario T10-B -Transport Real -AllowNetwork
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT10.ps1 -Scenario T10-C -Transport Real -AllowNetwork
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT10.ps1 -Scenario T10-D -Transport Real -AllowNetwork
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT10.ps1 -Scenario T10-E -Transport Real -AllowNetwork
```

Cada escenario realiza dos solicitudes. Antes de **cada una**, active manualmente `Execute workflow` en n8n y escriba `EJECUTAR`; T10-A requiere expresamente dos activaciones independientes. T10-C pide confirmar que existe una segunda cuenta y queda en SKIP si no esta disponible. T10-D no solicita credenciales porque prueba ausencia de autenticacion y token ficticio. T10-E usa autenticacion real y prueba conversationId ausente e invalido.

T10 usa un marcador sintetico para producir una senal automatica limitada de recuerdo o aislamiento, pero no guarda conversationId, mensajes ni respuestas. Incluso con `automaticStatus: PASS`, tanto `manualEvaluation` como `postgresStorageVerification` permanecen en `PENDING`. La memoria no debe considerarse demostrada hasta revisar las respuestas reales y verificar el almacenamiento o la ausencia de escritura en PostgreSQL mediante un canal autorizado.

Para T10-D y T10-E, el reporte incluye `requestDiagnostics` separado para cada solicitud: HTTP esperado y observado, validez JSON, presencia del campo `error`, coincidencia booleana de su valor y un codigo de diagnostico. No se guardan cuerpos ni valores inesperados. Los codigos posibles son `contract_match`, `http_status_mismatch`, `invalid_json`, `missing_error_field` y `error_value_mismatch`.

## T11: agente Nébula con MCP curricular

T11 envia una pregunta autenticada sobre las materias del tercer semestre mediante el webhook-test del workflow principal. Primero ejecute los autocontroles sin red:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT11Offline.ps1
```

Ejecucion real interactiva:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT11.ps1 -Transport Real -AllowNetwork
```

El contrato automatico exige HTTP 200, JSON valido, `success` booleano `true` y `response` textual significativa. La respuesta se muestra en terminal pero no se guarda. Debe compararse manualmente con siete posiciones y 17 creditos: Calculo en varias variables (3), Creatividad (3), Electromagnetismo y laboratorio (3), Estructura de datos y analisis de algoritmos (3), Laboratorio de electromagnetismo (0), Matematicas computacionales (3) y Seminario de ingenieria II (2). No deben presentarse prerrequisitos como confirmados si su cobertura es `unknown`.

Aunque la respuesta sea correcta, `academicEvaluation` y `mcpExecutionEvidence` permanecen en `PENDING`. Confirme visualmente en la ejecucion de n8n que el AI Agent llamo a `MCP Curricular`; una respuesta correcta por si sola no demuestra el recorrido MCP.

## T12: RPC personales directas

T12 autentica una cuenta estudiantil y consulta directamente `get_academic_history()` y `get_credit_progress()` mediante Supabase REST, enviando `{}` a cada RPC. Autocontroles offline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT12Offline.ps1
```

Ejecucion real:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT12.ps1 -Transport Real -AllowNetwork
```

El runner pide `EJECUTAR` antes de cada RPC y solo muestra categoria (`DATA`, `NO_DATA` o error), cantidad de filas y validaciones estructurales. No imprime ni guarda historial, materias, notas, creditos personales, identificadores o credenciales.

Para ampliar T12 con aislamiento, use dos cuentas de prueba autorizadas, obtenga cada JWT por separado y llame ambas RPC con cada token. Compare solo huellas o conteos seguros preparados en un entorno aislado. Dos respuestas `NO_DATA` no demuestran aislamiento; se necesita al menos una cuenta con registros conocidos y distintos, sin insertar datos ficticios en la base principal.

## T13: herramientas personales desde el agente

Autocontroles offline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Test-NebulaT13Offline.ps1
```

Ejecuciones reales individuales:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT13.ps1 -Scenario T13-A -Transport Real -AllowNetwork
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\n8n\Invoke-NebulaT13.ps1 -Scenario T13-B -Transport Real -AllowNetwork
```

T13-A espera verificar visualmente `historial_academico`; una respuesta sin registros puede ser correcta. T13-B espera `progreso_creditos` y no presupone creditos aprobados por existir una fila. El PASS automatico solo valida HTTP 200, JSON, `success: true` y texto significativo. `academicEvaluation` y `toolExecutionEvidence` permanecen en `PENDING` hasta revisar la respuesta y la ejecucion n8n.

## Reportes

Cada proceso crea `tests/n8n/reports/TXX-*.json` con `PASS`, `FAIL` o `SKIP`, estado HTTP observado y errores de asercion. Los reportes y cualquier archivo local de evidencias estan ignorados por Git. Un FAIL significa que difirio el HTTP, falto/cambio una propiedad JSON, la respuesta no fue JSON o fallo el transporte. Un SKIP explica el prerrequisito ausente.
