# NébulaIA 2.0 — Aplicación móvil y web (Expo)

Frontend del asistente académico de la UNAB: Expo + React Native + TypeScript,
para Android y web. El código del frontend vive en [`src/ui/`](../src/ui) y no
modifica el backend (RAG, Supabase ni migraciones).

## Requisitos

- Node.js 20+ (probado con Node 24)
- npm 10+
- Expo SDK 58 (ya fijado en `package.json`)

## Instalar y ejecutar

```bash
npm install
npx expo start          # abre el panel de Expo (QR para Android con Expo Go)
npx expo start --web     # abre directamente la versión web
npx expo start --android # compila/abre en un dispositivo o emulador Android
```

Comprobaciones:

```bash
npx tsc --noEmit         # verificación de tipos (debe salir sin errores)
npx expo export -p web   # construye el bundle web (validación de empaquetado)
npx expo export -p android  # bundle Android

# Prueba del cliente HTTP de n8n (200 objeto/array, HTML, 400, 401, 404, 502):
node tests/frontend/n8n_contract.test.mjs
```

## Modo de demostración

Por defecto, la app funciona en **modo demostración**, claramente identificado en
cada pantalla, porque los workflows conversacionales de n8n están inactivos y
`RAG_ENABLED=false` del lado del servidor. En este modo:

- El chat responde con orientación general local (sin acceder a datos reales).
- Las pantallas académicas muestran un **perfil de ejemplo ficticio** (no es un
  estudiante real) con una advertencia visible.

El modo demo nunca se hace pasar por datos académicos reales.

## Autenticación (Supabase Auth)

- Proyecto: `https://icsekpkuheckfkgkqosg.supabase.co` (la URL es pública y ya
  viene como valor por defecto; se puede sobrescribir por entorno).
- Solo falta la **clave anónima pública** del proyecto para habilitar el login.
- Con la auth configurada, la app muestra una **pantalla de login**; restaura la
  sesión al abrir, permite cerrar sesión y maneja credenciales inválidas, errores
  de red y sesiones caducadas. La contraseña y el token nunca se imprimen.
- Sin clave anónima configurada, la app arranca directamente en **modo demo**
  (sin login), para poder probar la interfaz.

## Variables de entorno (públicas, prefijo `EXPO_PUBLIC_`)

Nunca se colocan aquí claves de Gemini, `service_role` de Supabase ni
credenciales de PostgreSQL. Cree un archivo `.env` (ignorado por git) con:

```bash
# Supabase Auth — la ANON KEY es, por diseño, una clave pública de cliente.
# La URL ya tiene valor por defecto; basta con la clave anónima:
EXPO_PUBLIC_SUPABASE_ANON_KEY=<anon-key-publica-del-proyecto>
# (opcional) EXPO_PUBLIC_SUPABASE_URL=https://icsekpkuheckfkgkqosg.supabase.co

# Webhook del workflow conversacional de n8n (contrato real del sandbox).
# Prueba (requiere "Listen for test event" en n8n):
EXPO_PUBLIC_N8N_WEBHOOK_URL=https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2-rag-sandbox/chat
# Producción del sandbox (aún no disponible):
# EXPO_PUBLIC_N8N_WEBHOOK_URL=https://sofinebula.app.n8n.cloud/webhook/nebula-v2-rag-sandbox/chat
EXPO_PUBLIC_CHAT_ENABLED=true
```

Modo **demo** vs **conectado**:

- **Demo**: sin sesión autenticada o sin webhook configurado. El chat responde con
  orientación general local y las pantallas académicas usan datos de ejemplo.
- **Conectado**: sesión Supabase activa **y** webhook configurado. La app realiza
  la llamada HTTP real. La conexión se marca como *Conectado* solo tras una
  **respuesta correcta** de n8n (no por el mero hecho de tener variables). Hasta
  entonces el encabezado muestra *Backend sin verificar*.

## Contrato real de n8n

```
POST <EXPO_PUBLIC_N8N_WEBHOOK_URL>
Headers: Authorization: Bearer <supabase_access_token>
         Content-Type: application/json
Body:    { "message": string(no vacío),
           "conversationId": "^[A-Za-z0-9_-]{8,64}$" }

200  { "success": true, "project": "Nebula 2.0", "response": "<texto real>" }
```

Errores gestionados con mensaje claro y reintento cuando procede:
`400 invalid_message`, `400 invalid_conversation_id`, `401 unauthorized`,
`502 agent_unavailable`, además de red y timeout. Una respuesta fallida **nunca**
se sustituye por una respuesta local simulada.

El `conversationId` se genera de forma segura y única por conversación, se
conserva mientras dura, se asocia al usuario autenticado (no se comparte entre
usuarios) y se limpia al cerrar sesión.

## El personaje Nébula

Las tres animaciones originales (`assets/GatoIdle.ase`, `GatoTalking.ase`,
`GatoThinking.ase`) se exportaron con LibreSprite a spritesheets PNG en
[`assets/nebula/`](../assets/nebula). Los `.ase` originales se conservan intactos.

| Animación     | Lienzo | Frames | ms/frame | Estado    |
|---------------|--------|--------|----------|-----------|
| GatoIdle      | 32×32  | 2      | 500      | idle      |
| GatoThinking  | 32×32  | 6      | 300      | thinking  |
| GatoTalking   | 32×32  | 2      | 500      | talking   |

Para regenerar los PNG desde los `.ase` (si se editan):

```bash
# LibreSprite (o Aseprite) en modo batch:
libresprite -b assets/GatoIdle.ase     --sheet-type horizontal --sheet assets/nebula/GatoIdle.png     --data assets/nebula/GatoIdle.json
libresprite -b assets/GatoTalking.ase  --sheet-type horizontal --sheet assets/nebula/GatoTalking.png  --data assets/nebula/GatoTalking.json
libresprite -b assets/GatoThinking.ase --sheet-type horizontal --sheet assets/nebula/GatoThinking.png --data assets/nebula/GatoThinking.json
```

La máquina de estados del personaje está en
[`src/ui/state/nebulaState.ts`](../src/ui/state/nebulaState.ts) y se vincula al
estado real del chat (nunca a temporizadores sueltos):

```
idle → (enviar) thinking → (respuesta) talking → (fin de presentación) idle
idle → (enviar) thinking → (error) idle
```
