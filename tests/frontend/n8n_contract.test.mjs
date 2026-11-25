/**
 * Prueba del cliente HTTP de n8n (lógica pura de interpretación del contrato).
 *
 * No requiere Jest ni dependencias nuevas: transpila src/ui/services/contract.ts
 * con el TypeScript ya instalado y ejecuta aserciones sobre interpretResponse con
 * respuestas simuladas (200 objeto, 200 array de n8n, 200 HTML, 400, 401, 404, 502)
 * y sobre el regex de conversationId.
 *
 * Ejecutar:  node tests/frontend/n8n_contract.test.mjs
 */
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ts = require('typescript');

const src = readFileSync(new URL('../../src/ui/services/contract.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(src, {
  compilerOptions: { module: 'ESNext', target: 'ES2020', isolatedModules: true },
}).outputText;

const dir = mkdtempSync(join(tmpdir(), 'nebula-contract-'));
const file = join(dir, 'contract.mjs');
writeFileSync(file, js);
const { interpretResponse, CONVERSATION_ID_RE } = await import(pathToFileURL(file).href);

let passed = 0;
function check(name, fn) {
  fn();
  passed += 1;
  console.log(`  ✓ ${name}`);
}

const JSON_CT = 'application/json; charset=utf-8';

console.log('interpretResponse:');

check('200 objeto { success, project, response } -> ok', () => {
  const r = interpretResponse(200, true, JSON_CT,
    JSON.stringify({ success: true, project: 'Nebula 2.0', response: 'Hola, soy Nébula.' }));
  assert.equal(r.kind, 'ok');
  assert.equal(r.reply, 'Hola, soy Nébula.');
});

check('200 ARRAY de n8n [ { success, response } ] -> ok (bug corregido)', () => {
  const r = interpretResponse(200, true, JSON_CT,
    JSON.stringify([{ success: true, project: 'Nebula 2.0', response: 'Respuesta real.' }]));
  assert.equal(r.kind, 'ok');
  assert.equal(r.reply, 'Respuesta real.');
});

check('200 envoltorio { json: { response } } -> ok', () => {
  const r = interpretResponse(200, true, JSON_CT,
    JSON.stringify({ json: { success: true, response: 'Desde json.' } }));
  assert.equal(r.kind, 'ok');
  assert.equal(r.reply, 'Desde json.');
});

check('200 HTML (túnel/error) -> bad_response', () => {
  const r = interpretResponse(200, true, 'text/html', '<!DOCTYPE html><html>...</html>');
  assert.equal(r.kind, 'error');
  assert.equal(r.code, 'bad_response');
});

check('200 success:false -> agent_unavailable', () => {
  const r = interpretResponse(200, true, JSON_CT, JSON.stringify({ success: false }));
  assert.equal(r.kind, 'error');
  assert.equal(r.code, 'agent_unavailable');
});

check('400 invalid_message', () => {
  const r = interpretResponse(400, false, JSON_CT, JSON.stringify({ error: 'invalid_message' }));
  assert.equal(r.code, 'invalid_message');
});

check('400 invalid_conversation_id', () => {
  const r = interpretResponse(400, false, JSON_CT, JSON.stringify({ error: 'invalid_conversation_id' }));
  assert.equal(r.code, 'invalid_conversation_id');
});

check('401 unauthorized', () => {
  const r = interpretResponse(401, false, JSON_CT, JSON.stringify({ error: 'unauthorized' }));
  assert.equal(r.code, 'unauthorized');
});

check('404 -> not_found (webhook no activo)', () => {
  const r = interpretResponse(404, false, JSON_CT,
    JSON.stringify({ message: 'webhook not registered' }));
  assert.equal(r.code, 'not_found');
});

check('502 agent_unavailable', () => {
  const r = interpretResponse(502, false, JSON_CT, JSON.stringify({ error: 'agent_unavailable' }));
  assert.equal(r.code, 'agent_unavailable');
});

console.log('CONVERSATION_ID_RE:');
check('acepta id válido de 36 chars', () => {
  assert.ok(CONVERSATION_ID_RE.test('nebula_conv_ABCdef0123456789ABCDEF12'));
});
check('rechaza id corto (<8)', () => {
  assert.ok(!CONVERSATION_ID_RE.test('short'));
});
check('rechaza caracteres inválidos', () => {
  assert.ok(!CONVERSATION_ID_RE.test('nebula conv con espacios!'));
});

console.log(`\n${passed} comprobaciones superadas.`);
