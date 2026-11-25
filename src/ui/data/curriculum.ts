/**
 * Malla curricular de referencia: Ingeniería de Sistemas UNAB.
 * Plan histórico (antiguo) de 9 semestres y 151 créditos.
 *
 * Fuente: migración académica del propio repositorio
 * (supabase/migrations/20261124020000_academic_catalog_seed.sql),
 * derivada de los CSV originales validados. No se sustituye por otra malla.
 * Identificador de plan: NEBULA-UNAB-IS-9S-V1.
 */

export type Subject = {
  id: string;
  name: string;
  credits: number;
  semester: number;
  position: number;
};

export const CURRICULUM_PLAN = {
  id: 'NEBULA-UNAB-IS-9S-V1',
  program: 'Ingeniería de Sistemas',
  institution: 'Universidad Autónoma de Bucaramanga (UNAB)',
  semesters: 9,
  totalCredits: 151,
  totalSubjects: 51,
} as const;

export const SUBJECTS: Subject[] = [
  { id: 'S01-P01', name: 'Álgebra lineal', credits: 3, semester: 1, position: 1 },
  { id: 'S01-P02', name: 'Cálculo diferencial', credits: 4, semester: 1, position: 2 },
  { id: 'S01-P03', name: 'Expresión', credits: 4, semester: 1, position: 3 },
  { id: 'S01-P04', name: 'Fundamentos de programación', credits: 3, semester: 1, position: 4 },
  { id: 'S01-P05', name: 'Seminario de ingeniería I', credits: 2, semester: 1, position: 5 },

  { id: 'S02-P01', name: 'Cálculo integral', credits: 4, semester: 2, position: 1 },
  { id: 'S02-P02', name: 'Diseño de interfaces de usuario', credits: 3, semester: 2, position: 2 },
  { id: 'S02-P03', name: 'Identidad', credits: 3, semester: 2, position: 3 },
  { id: 'S02-P04', name: 'Laboratorio de mecánica', credits: 0, semester: 2, position: 4 },
  { id: 'S02-P05', name: 'Mecánica y laboratorio', credits: 3, semester: 2, position: 5 },
  { id: 'S02-P06', name: 'Programación de computadores', credits: 3, semester: 2, position: 6 },
  { id: 'S02-P07', name: 'Taller de deportes, recreación y cultura', credits: 1, semester: 2, position: 7 },
  { id: 'S02-P08', name: 'Taller de desarrollo humano', credits: 1, semester: 2, position: 8 },

  { id: 'S03-P01', name: 'Cálculo en varias variables', credits: 3, semester: 3, position: 1 },
  { id: 'S03-P02', name: 'Creatividad', credits: 3, semester: 3, position: 2 },
  { id: 'S03-P03', name: 'Electromagnetismo y laboratorio', credits: 3, semester: 3, position: 3 },
  { id: 'S03-P04', name: 'Estructura de datos y análisis de algoritmos', credits: 3, semester: 3, position: 4 },
  { id: 'S03-P05', name: 'Laboratorio de electromagnetismo', credits: 0, semester: 3, position: 5 },
  { id: 'S03-P06', name: 'Matemáticas computacionales', credits: 3, semester: 3, position: 6 },
  { id: 'S03-P07', name: 'Seminario de ingeniería II', credits: 2, semester: 3, position: 7 },

  { id: 'S04-P01', name: 'Base de datos I', credits: 3, semester: 4, position: 1 },
  { id: 'S04-P02', name: 'Desarrollo multimedia', credits: 3, semester: 4, position: 2 },
  { id: 'S04-P03', name: 'Ecuaciones diferenciales', credits: 3, semester: 4, position: 3 },
  { id: 'S04-P04', name: 'Estadística general', credits: 3, semester: 4, position: 4 },
  { id: 'S04-P05', name: 'Inteligencia artificial', credits: 3, semester: 4, position: 5 },
  { id: 'S04-P06', name: 'Tecnologías móviles', credits: 3, semester: 4, position: 6 },

  { id: 'S05-P01', name: 'Actividades libres de recreación, deporte y cultura y de desarrollo humano', credits: 2, semester: 5, position: 1 },
  { id: 'S05-P02', name: 'Arquitectura de software', credits: 3, semester: 5, position: 2 },
  { id: 'S05-P03', name: 'Base de datos II', credits: 3, semester: 5, position: 3 },
  { id: 'S05-P04', name: 'Electiva de profundización', credits: 3, semester: 5, position: 4 },
  { id: 'S05-P05', name: 'Infraestructura tecnológica', credits: 3, semester: 5, position: 5 },
  { id: 'S05-P06', name: 'Ingeniería de software I', credits: 3, semester: 5, position: 6 },

  { id: 'S06-P01', name: 'Ciencias de datos', credits: 3, semester: 6, position: 1 },
  { id: 'S06-P02', name: 'Electiva de profundización', credits: 3, semester: 6, position: 2 },
  { id: 'S06-P03', name: 'Ética de la ingeniería de sistemas', credits: 2, semester: 6, position: 3 },
  { id: 'S06-P04', name: 'Ingeniería de software II', credits: 3, semester: 6, position: 4 },
  { id: 'S06-P05', name: 'Internet de las cosas', credits: 3, semester: 6, position: 5 },
  { id: 'S06-P06', name: 'Teoría de sistemas y organizaciones', credits: 3, semester: 6, position: 6 },

  { id: 'S07-P01', name: 'Ciberseguridad', credits: 3, semester: 7, position: 1 },
  { id: 'S07-P02', name: 'Electiva sociohumanística', credits: 3, semester: 7, position: 2 },
  { id: 'S07-P03', name: 'Electiva de contexto', credits: 3, semester: 7, position: 3 },
  { id: 'S07-P04', name: 'Electiva de profundización', credits: 3, semester: 7, position: 4 },
  { id: 'S07-P05', name: 'Investigación de operaciones I', credits: 3, semester: 7, position: 5 },
  { id: 'S07-P06', name: 'Proyecto en ingeniería de sistemas I', credits: 2, semester: 7, position: 6 },

  { id: 'S08-P01', name: 'Dinámica de sistemas', credits: 3, semester: 8, position: 1 },
  { id: 'S08-P02', name: 'Electiva sociohumanística', credits: 3, semester: 8, position: 2 },
  { id: 'S08-P03', name: 'Electiva de profundización', credits: 3, semester: 8, position: 3 },
  { id: 'S08-P04', name: 'Investigación de operaciones II', credits: 3, semester: 8, position: 4 },
  { id: 'S08-P05', name: 'Proyecto en ingeniería de sistemas II', credits: 4, semester: 8, position: 5 },

  { id: 'S09-P01', name: 'Electiva de contexto', credits: 3, semester: 9, position: 1 },
  { id: 'S09-P02', name: 'Práctica en ingeniería de sistemas', credits: 12, semester: 9, position: 2 },
];

export function subjectsBySemester(semester: number): Subject[] {
  return SUBJECTS.filter((s) => s.semester === semester).sort((a, b) => a.position - b.position);
}

export function creditsForSemester(semester: number): number {
  return subjectsBySemester(semester).reduce((sum, s) => sum + s.credits, 0);
}

export const SEMESTERS: number[] = Array.from({ length: CURRICULUM_PLAN.semesters }, (_, i) => i + 1);
