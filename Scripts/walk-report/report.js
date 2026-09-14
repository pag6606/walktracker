#!/usr/bin/env node
'use strict';
/**
 * Informe de la caminata del gate 8.4 a partir del registro de medición de la app.
 *
 * Lee texto: la salida de `log show` en estilo `default`, `compact` o `syslog` (una entrada
 * por línea), o un fichero ya exportado así. Los estilos `json` y `ndjson` se rechazan. Solo
 * interesan las líneas que contienen `WTM<versión> `; lo que va antes (fecha, proceso,
 * subsistema) se ignora. El formato lo escribe `WalkTracker/Application/MeasurementLog.swift`
 * y la fixture compartida `WalkTrackerTests/Application/MeasurementLogFixture.txt` lo fija
 * en los dos lados: si cambias uno, cambia el otro.
 *
 *   WTM1 event=<sample|query|queryLate|estimate|session> sid=<ms> clave=valor …
 *
 * Por sesión (`sid`) escribe: build de la app, duración, pasos y distancia finales,
 * `stepsEstimated` frente al criterio, consultas (número, duración máxima y p95 reales,
 * desenlaces, respuestas tardías), muestras con y sin distancia, los avisos de R1 (consulta
 * menor que lo visto), estimaciones, R2 (muestra del stream que sube tras una consulta
 * degradada) y R5, y la propuesta de `reconciliationTimeoutS` según la regla decidida por Paul:
 * max(1 s, 5 × duración máxima), redondeado hacia arriba al segundo. Una consulta que agotó el
 * timeout cuenta con la duración de su `queryLate`; sin ella, no se propone valor.
 *
 * Sale ≠ 0, con un mensaje claro, si no hay ninguna línea de medición, si hay una versión que
 * no conoce, si los valores salen como `<private>` o si una línea está mal formada.
 *
 * Uso: node Scripts/walk-report/report.js [FICHERO]   (sin fichero, lee stdin)
 */

const fs = require('fs');

const VERSION = 1;

/** Claves obligatorias por evento, en el orden en que las escribe la app. */
const SCHEMA = {
    sample: ['sid', 'start', 'end', 'steps', 'distance'],
    query: ['sid', 'start', 'end', 'result', 'distance', 'seen', 'ms', 'outcome'],
    queryLate: ['sid', 'start', 'end', 'result', 'distance', 'seen', 'ms', 'outcome'],
    estimate: ['sid', 'gapStart', 'gapEnd', 'steps', 'skipped'],
    session: ['sid', 'transition', 'at', 'status', 'elapsedS', 'measured', 'estimated', 'systemDistance', 'distance'],
};
const OUTCOMES = ['data', 'nil', 'timeout', 'belowSeen', 'error'];
const DEGRADED = new Set(['nil', 'timeout', 'belowSeen', 'error']);

class ReportError extends Error {}

function fail(message) {
    throw new ReportError(message);
}

// ── Parseo ────────────────────────────────────────────────────────────────

function parse(text) {
    if (/^\s*[\[{]/.test(text)) {
        fail('el registro está en estilo json/ndjson y este informe no lo lee. ' +
            'Exporta con `log show --style compact` (o default/syslog), o pasa el .logarchive a walk-report.sh.');
    }
    const events = [];
    const lines = text.split(/\r?\n/);
    lines.forEach((raw, index) => {
        const at = raw.search(/WTM\d+ /);
        if (at < 0) return;
        const lineNo = index + 1;
        const body = raw.slice(at).trim();
        const version = Number(body.match(/^WTM(\d+) /)[1]);
        if (version !== VERSION) {
            fail(`línea ${lineNo}: formato WTM${version} desconocido; este informe solo lee WTM${VERSION}. ¿App y script de versiones distintas?`);
        }
        if (body.includes('<private>')) {
            fail(`línea ${lineNo}: los valores salen como <private>. La app debe registrar la medición como pública (MeasurementLog.record).`);
        }
        const fields = {};
        for (const token of body.split(/\s+/).slice(1)) {
            const eq = token.indexOf('=');
            if (eq <= 0) fail(`línea ${lineNo}: campo mal formado '${token}'`);
            fields[token.slice(0, eq)] = token.slice(eq + 1);
        }
        const event = fields.event;
        if (!Object.hasOwn(SCHEMA, event)) fail(`línea ${lineNo}: evento desconocido '${event}'`);
        const keys = SCHEMA[event];
        const missing = keys.filter(k => !(k in fields));
        if (missing.length) fail(`línea ${lineNo}: a '${event}' le faltan ${missing.join(', ')}`);
        events.push(typed(event, fields, lineNo));
    });
    if (events.length === 0) {
        fail('el registro no tiene ninguna línea de medición (WTM1). ¿Es el registro de la caminata? ' +
            'Extráelo con `sudo log collect --device --last 2h` y pasa el .logarchive.');
    }
    return events;
}

function typed(event, f, lineNo) {
    const int = key => {
        if (!/^-?\d+$/.test(f[key])) fail(`línea ${lineNo}: '${key}' no es un entero: '${f[key]}'`);
        return Number(f[key]);
    };
    const num = key => {
        if (f[key] === 'nil') return null;
        const value = Number(f[key]);
        if (f[key] === '' || !Number.isFinite(value)) fail(`línea ${lineNo}: '${key}' no es un número: '${f[key]}'`);
        return value;
    };
    const base = { event, lineNo, sid: int('sid') };
    switch (event) {
        case 'sample':
            return { ...base, start: int('start'), end: int('end'), steps: int('steps'), distance: num('distance') };
        case 'query':
        case 'queryLate':
            if (!OUTCOMES.includes(f.outcome)) fail(`línea ${lineNo}: desenlace desconocido '${f.outcome}'`);
            return {
                ...base, start: int('start'), end: int('end'),
                result: f.result === 'nil' ? null : int('result'), distance: num('distance'),
                seen: int('seen'), ms: int('ms'), outcome: f.outcome,
            };
        case 'estimate':
            return { ...base, gapStart: int('gapStart'), gapEnd: int('gapEnd'), steps: int('steps'), skipped: f.skipped === 'nil' ? null : f.skipped };
        case 'session':
            return {
                ...base, transition: f.transition, at: int('at'), status: f.status, elapsedS: int('elapsedS'),
                measured: int('measured'), estimated: int('estimated'),
                systemDistance: num('systemDistance'), distance: num('distance'),
                version: f.version ?? null, build: f.build ?? null,
            };
    }
}

// ── Análisis ──────────────────────────────────────────────────────────────

/** p-ésimo percentil por rango más cercano. */
function percentile(values, p) {
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)];
}

function analyze(events) {
    const sessions = new Map();
    for (const e of events) {
        if (!sessions.has(e.sid)) sessions.set(e.sid, []);
        sessions.get(e.sid).push(e);
    }
    return [...sessions.entries()].map(([sid, list]) => analyzeSession(sid, list));
}

function analyzeSession(sid, list) {
    const samples = list.filter(e => e.event === 'sample');
    const queries = list.filter(e => e.event === 'query');
    const lateQueries = list.filter(e => e.event === 'queryLate');
    const allEstimates = list.filter(e => e.event === 'estimate');
    const estimates = allEstimates.filter(e => e.skipped === null);
    const skippedEstimates = allEstimates.filter(e => e.skipped !== null);
    const transitions = list.filter(e => e.event === 'session');
    const finish = transitions.find(e => e.transition === 'finish' || e.transition === 'orphan');
    const last = finish || transitions[transitions.length - 1] || null;
    const opening = [...transitions].reverse().find(e => e.version !== null);
    const discarded = transitions.some(e => e.transition === 'discardEstimated');
    const warnings = [];

    if (!transitions.some(e => e.transition === 'start' || e.transition === 'restore')) {
        warnings.push('el registro no incluye el inicio de la sesión: puede faltar el principio (¿`--last` corto?)');
    }
    if (!finish) warnings.push('la sesión no está finalizada en el registro: los valores finales son los de la última transición');

    // R1: consulta menor que lo visto.
    for (const q of queries.filter(q => q.outcome === 'belowSeen')) {
        warnings.push(`R1 · consulta menor que lo visto (línea ${q.lineNo}): result=${q.result} < seen=${q.seen} ` +
            `(−${q.seen - q.result} pasos); hoy cuenta como sin dato`);
    }
    // Estimaciones.
    for (const e of estimates) {
        const minutes = ((e.gapEnd - e.gapStart) / 60000).toFixed(1);
        warnings.push(`estimación (línea ${e.lineNo}): ${e.steps} pasos para un gap de ${minutes} min`);
    }
    for (const e of skippedEstimates) {
        warnings.push(`estimación omitida (línea ${e.lineNo}): ${e.skipped}; el stream avanzó durante la consulta degradada`);
    }
    if (discarded) warnings.push('se descartaron pasos estimados durante la sesión');
    // R2: tras una consulta degradada, la primera muestra del stream del mismo tramo (inicio a
    // menos de 1 s) que sube por encima de lo visto, antes de la consulta siguiente.
    queries.forEach((q, index) => {
        if (!DEGRADED.has(q.outcome)) return;
        const nextLine = index + 1 < queries.length ? queries[index + 1].lineNo : Infinity;
        const after = samples.find(s => s.lineNo > q.lineNo && s.lineNo < nextLine &&
            Math.abs(s.start - q.start) < 1000 && s.steps > q.seen);
        if (!after) return;
        const estimated = estimates.filter(e => e.lineNo > q.lineNo && e.lineNo < after.lineNo)
            .reduce((sum, e) => sum + e.steps, 0);
        const jump = after.steps - q.seen;
        const doubleCount = estimated > 0 && jump >= estimated / 2;
        warnings.push(`R2 · tras la consulta ${q.outcome} (línea ${q.lineNo}, seen=${q.seen}) el stream sube a ` +
            `${after.steps} (+${jump}, línea ${after.lineNo}) con ${estimated} pasos estimados entre medias` +
            (doubleCount ? ': posible doble cuenta' : ''));
    });

    // Duraciones reales: una consulta con timeout cuenta con su respuesta tardía; sin ella, es
    // desconocida y no se propone timeout.
    const usedLate = new Set();
    const durations = [];
    let censored = 0;
    for (const q of queries) {
        if (q.outcome !== 'timeout') {
            durations.push(q.ms);
            continue;
        }
        const late = lateQueries.find(l => !usedLate.has(l) && l.lineNo > q.lineNo && l.start === q.start && l.end === q.end);
        if (late) {
            usedLate.add(late);
            durations.push(late.ms);
        } else {
            censored++;
        }
    }
    if (censored > 0) {
        warnings.push(`${censored} consulta(s) agotaron el timeout sin respuesta tardía registrada: su duración real es desconocida`);
    }
    if (transitions.some(e => e.transition === 'streamEnded')) {
        warnings.push('R5 · el sistema terminó el stream del podómetro durante la sesión');
    }

    const withDistance = samples.filter(s => s.distance !== null).length;
    let alternations = 0;
    for (let i = 1; i < samples.length; i++) {
        if ((samples[i].distance === null) !== (samples[i - 1].distance === null)) alternations++;
    }
    const outcomes = Object.fromEntries(OUTCOMES.map(o => [o, queries.filter(q => q.outcome === o).length]));
    const lateOutcomes = Object.fromEntries(OUTCOMES.map(o => [o, lateQueries.filter(q => q.outcome === o).length]));
    const maxMs = durations.length ? Math.max(...durations) : null;

    const estimated = last ? last.estimated : null;
    let criterion;
    if (estimated === null) criterion = 'sin datos';
    else if (discarded) criterion = 'NO CUMPLE (estimados descartados)';
    else if (estimated !== 0 || estimates.some(e => e.steps > 0)) criterion = 'NO CUMPLE';
    else if (!finish) criterion = 'NO CUMPLE (sesión sin finalizar)';
    else criterion = 'cumple';

    let timeoutProposal;
    if (queries.length === 0) timeoutProposal = 'sin consultas en la sesión, no hay duración que medir';
    else if (censored > 0) timeoutProposal = 'no se propone: hay consultas con timeout sin duración real';
    else timeoutProposal = `${Math.max(1, Math.ceil((5 * maxMs) / 1000))} s = max(1 s, 5 × ${maxMs} ms), redondeado hacia arriba`;

    return {
        sid,
        build: opening ? `${opening.version} (${opening.build})` : null,
        finished: Boolean(finish),
        elapsedS: last ? last.elapsedS : null,
        wallS: last ? Math.round((last.at - sid) / 1000) : null,
        measured: last ? last.measured : null,
        estimated,
        criterion,
        systemDistance: last ? last.systemDistance : null,
        distance: last ? last.distance : null,
        transitions: transitions.map(e => e.transition),
        queries: {
            count: queries.length, maxMs, p95Ms: durations.length ? percentile(durations, 95) : null, outcomes,
            late: lateQueries.length, lateOutcomes,
        },
        samples: { total: samples.length, withDistance, withoutDistance: samples.length - withDistance, alternations },
        estimates: { count: estimates.length, steps: estimates.reduce((sum, e) => sum + e.steps, 0), skipped: skippedEstimates.length },
        timeoutProposal,
        warnings,
    };
}

// ── Salida ────────────────────────────────────────────────────────────────

function clock(seconds) {
    if (seconds === null || seconds < 0) return '—';
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m} min ${String(s).padStart(2, '0')} s`;
}

function meters(value) {
    return value === null ? 'nil' : `${value.toFixed(2)} m`;
}

function render(reports) {
    const out = [];
    out.push('Informe de la caminata · gate 8.4');
    if (reports.length > 1) out.push(`⚠️  el registro contiene ${reports.length} sesiones; se informa cada una`);
    for (const r of reports) {
        out.push('');
        out.push(`── Sesión sid=${r.sid} (${new Date(r.sid).toISOString()}) ──`);
        out.push(`Build: ${r.build ?? '—'}`);
        out.push(`Finalizada: ${r.finished ? 'sí' : 'no'} · transiciones: ${r.transitions.join(' → ') || '—'}`);
        out.push(`Duración neta: ${clock(r.elapsedS)} (${r.elapsedS ?? '—'} s) · de reloj: ${clock(r.wallS)}`);
        out.push(`Pasos: ${r.measured === null ? '—' : r.measured + r.estimated} (medidos ${r.measured ?? '—'} + estimados ${r.estimated ?? '—'})`);
        out.push(`Distancia: ${meters(r.distance)} · del sistema: ${meters(r.systemDistance)}`);
        out.push(`stepsEstimated: ${r.estimated ?? '—'} · criterio del gate = 0: ${r.criterion}`);
        const q = r.queries;
        out.push(`Consultas: ${q.count} · duración máx.: ${q.maxMs ?? '—'} ms · p95: ${q.p95Ms ?? '—'} ms`);
        out.push(`Desenlaces: ${OUTCOMES.map(o => `${o}=${q.outcomes[o]}`).join(' ')}`);
        out.push(`Respuestas tardías: ${q.late}${q.late ? ` (${OUTCOMES.filter(o => q.lateOutcomes[o]).map(o => `${o}=${q.lateOutcomes[o]}`).join(' ')})` : ''}`);
        const s = r.samples;
        out.push(`Muestras del stream: ${s.total} · con distancia: ${s.withDistance} · sin distancia: ${s.withoutDistance} · alternancias: ${s.alternations}`);
        out.push(`Estimaciones: ${r.estimates.count} (${r.estimates.steps} pasos) · omitidas: ${r.estimates.skipped}`);
        if (r.warnings.length === 0) {
            out.push('Avisos: ninguno (sin R1, sin estimaciones, sin R2)');
        } else {
            out.push('Avisos:');
            r.warnings.forEach(w => out.push(`  ⚠️  ${w}`));
        }
        out.push(`reconciliationTimeoutS propuesto: ${r.timeoutProposal}`);
    }
    return out.join('\n');
}

function main() {
    const file = process.argv[2];
    let text;
    try {
        text = file ? fs.readFileSync(file, 'utf8') : fs.readFileSync(0, 'utf8');
    } catch (error) {
        console.error(`walk-report: no se puede leer ${file || 'stdin'}: ${error.message}`);
        process.exit(2);
    }
    try {
        console.log(render(analyze(parse(text))));
    } catch (error) {
        if (!(error instanceof ReportError)) throw error;
        console.error(`walk-report: ${error.message}`);
        process.exit(1);
    }
}

if (require.main === module) main();

module.exports = { parse, analyze, render };
