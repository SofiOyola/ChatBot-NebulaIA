# Pruebas de seguridad de RPC

Esta suite usa Supabase Auth real, llama los RPC por PostgREST y prepara dos usuarios efimeros mediante una conexion administrativa al PostgreSQL de **un proyecto de pruebas**. No altera las funciones SQL ni usa cuentas existentes. Al terminar elimina únicamente los UUID creados por la propia ejecucion.

## Preparacion segura (PowerShell)

1. Cree un proyecto Supabase desechable y aplique allí las migraciones `001` a `004`.
2. Copie `.env.example` como `.env.test` y complete solo credenciales de ese proyecto.
3. Confirme que `.env.test` contiene `NEBULA_TEST_ENV=true`.
4. Instale y ejecute:

```powershell
python -m venv .venv
Set-ExecutionPolicy -Scope Process Bypass
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-test.txt
python -m pytest -v --junitxml=tests/reports/junit.xml
```

Sin la marca de aislamiento o sin credenciales, las pruebas quedan en `SKIP`; no intentan crear usuarios ni filas. El resumen legible por herramientas queda en `tests/reports/junit.xml` y el reporte explícito PASS/FAIL/SKIP en `tests/reports/latest.json`. Cada FAIL incluye la asercion y la respuesta HTTP/SQL relevante.

Los secretos se cargan desde `.env.test`, ya cubierto por `.gitignore`. La `service_role` se usa exclusivamente en el runner para crear y eliminar usuarios efimeros; nunca debe copiarse a una aplicacion cliente.
