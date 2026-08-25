import { assertEquals } from 'jsr:@std/assert@1';
import { matchSkills } from './matching.ts';

Deno.test('matching is a set comparison, not a judgement call', () => {
  const result = matchSkills(
    ['JavaScript', 'React', 'CSS', 'Docker'],
    ['JavaScript', 'React', 'Python'],
  );
  assertEquals(result.matchPercent, 50);
  assertEquals(result.matched, ['JavaScript', 'React']);
  assertEquals(result.missing, ['CSS', 'Docker']);
});

Deno.test('spelling and punctuation do not lose a match', () => {
  const result = matchSkills(['Node.js', 'REST APIs'], ['nodejs', 'rest apis']);
  assertEquals(result.matchPercent, 100);
  assertEquals(result.missing, []);
});

Deno.test('a job asking for nothing scores zero rather than dividing by zero', () => {
  assertEquals(matchSkills([], ['Python']).matchPercent, 0);
});

Deno.test('a student with nothing matches nothing', () => {
  const result = matchSkills(['Python', 'SQL'], []);
  assertEquals(result.matchPercent, 0);
  assertEquals(result.missing, ['Python', 'SQL']);
});

Deno.test('a duplicated requirement is only counted once', () => {
  const result = matchSkills(['React', 'react', 'React '], ['React']);
  assertEquals(result.matchPercent, 100);
  assertEquals(result.matched.length, 1);
});

Deno.test('the same inputs always give the same answer', () => {
  const required = ['Python', 'SQL', 'Excel', 'Power BI'];
  const have = ['python', 'excel'];
  const first = matchSkills(required, have);
  for (let i = 0; i < 50; i++) {
    const again = matchSkills(required, have);
    assertEquals(again.matchPercent, first.matchPercent);
    assertEquals(again.matched, first.matched);
    assertEquals(again.missing, first.missing);
  }
});

Deno.test('the original wording is preserved for display', () => {
  // The student should see "Power BI", not "powerbi".
  const result = matchSkills(['Power BI'], ['power bi']);
  assertEquals(result.matched, ['Power BI']);
});
