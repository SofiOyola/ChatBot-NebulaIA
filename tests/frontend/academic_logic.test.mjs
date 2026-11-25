/**
 * Pruebas de la lógica académica pura (sin Jest ni dependencias nativas).
 * Transpila con el TypeScript instalado y verifica:
 *   - Semestre 6 → matrícula muestra semestre 7.
 *   - Semestre 9 → no aparece semestre 10 (kind 'last').
 *   - Créditos desconocidos → no se inventan (null).
 *   - La malla real tiene 9 semestres y 151 créditos (no hay semestre 10).
 *
 * Ejecutar:  node tests/frontend/academic_logic.test.mjs
 */
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ts = require('typescript');

function loadTs(relPath) {
  const src = readFileSync(new URL(relPath, import.meta.url), 'utf8');
  const js = ts.transpileModule(src, {
    compilerOptions: { module: 'ESNext', target: 'ES2020', isolatedModules: true },
  }).outputText;
  const dir = mkdtempSync(join(tmpdir(), 'nebula-'));
  const file = join(dir, 'mod.mjs');
  writeFileSync(file, js);
  return import(pathToFileURL(file).href);
}

const logic = await loadTs('../../src/ui/services/academicLogic.ts');
const curriculum = await loadTs('../../src/ui/data/curriculum.ts');

let passed = 0;
function check(name, fn) {
  fn();
  passed += 1;
  console.log(`  ✓ ${name}`);
}

console.log('nextSemesterPlan:');
check('semestre 6 → siguiente 7', () => {
  const p = logic.nextSemesterPlan(6, 9);
  assert.equal(p.kind, 'next');
  assert.equal(p.nextSemester, 7);
});
check('semestre 9 → último (no hay 10)', () => {
  const p = logic.nextSemesterPlan(9, 9);
  assert.equal(p.kind, 'last');
  assert.ok(!('nextSemester' in p) || p.nextSemester === undefined);
});
check('semestre null → desconocido', () => {
  assert.equal(logic.nextSemesterPlan(null, 9).kind, 'unknown');
});

console.log('deriveApprovedCredits:');
check('sin progreso de créditos → desconocido (null)', () => {
  const r = logic.deriveApprovedCredits(null, 0);
  assert.equal(r.approved, null);
  assert.equal(r.pending, null);
});
check('perfil sin historial → no inventa créditos (null)', () => {
  const r = logic.deriveApprovedCredits({ verifiedApproved: 0, reportedApproved: 0, pending: 151 }, 0);
  assert.equal(r.approved, null);
  assert.equal(r.pending, null);
});
check('con registros reales → usa créditos conocidos', () => {
  const r = logic.deriveApprovedCredits({ verifiedApproved: 80, reportedApproved: 6, pending: 65 }, 20);
  assert.equal(r.approved, 86);
  assert.equal(r.pending, 65);
});

console.log('malla curricular:');
check('semestre 7 tiene asignaturas reales', () => {
  const s7 = curriculum.subjectsBySemester(7);
  assert.ok(s7.length > 0);
  assert.ok(s7.every((s) => s.semester === 7));
});
check('la malla tiene 9 semestres y 151 créditos; no existe semestre 10', () => {
  assert.equal(curriculum.CURRICULUM_PLAN.semesters, 9);
  assert.equal(curriculum.CURRICULUM_PLAN.totalCredits, 151);
  assert.equal(curriculum.subjectsBySemester(10).length, 0);
  const total = curriculum.SUBJECTS.reduce((n, s) => n + s.credits, 0);
  assert.equal(total, 151);
});

console.log(`\n${passed} comprobaciones superadas.`);
