# AGENTS.md

Reglas de proyecto para agentes (OpenCode + BMAD). Son **invariantes**, no sugerencias.
Mantener este archivo corto: se carga en cada sesión de agente y su tamaño es costo de contexto.

## Fuente de verdad y trazabilidad
- Los artefactos del repo (`_bmad-output/**`: brief, PRD, architecture, epics) y engram son la **fuente de verdad**. Tu contexto de sesión no lo es.
- Ante conflicto entre contexto y artefacto/engram, **prevalece el artefacto/engram**.
- Todo valor normativo, regulatorio o de NFR citado en un artefacto debe incluir su fuente (p. ej. `[fuente: prd.md#NFR-9]`). Un valor sin fuente es un artefacto incompleto.

## Recuperación-antes-de-commit
No confíes en el recall del contexto para datos de baja saliencia o alto costo de error. Antes de afirmar o finalizar cualquiera de estos, recupéralo de su fuente (artefacto o engram) con una consulta **explícita** y cítalo:
- identificadores de control normativo/regulatorio (p. ej. códigos `KM-####`),
- restricciones de cumplimiento (longitudes, formatos, dígitos exactos),
- valores numéricos de NFR (latencias, umbrales, SLAs),
- nombres canónicos de bounded contexts o aggregates.

No parafrasees estos valores de memoria.

## Arquitectura (invariantes)
- **Hexagonal:** el dominio no depende de framework ni infraestructura. Nada de anotaciones JPA/Spring, I/O ni clientes de infra en entidades/value objects de dominio.
- **Regla de dependencia:** las dependencias apuntan hacia el dominio, nunca al revés. Puertos (interfaces) en el núcleo; adaptadores en el borde.
- **DDD:** respeta las fronteras de bounded context. No compartas modelos de dominio entre contextos.
- **Validación en la frontera:** las reglas de dominio se validan en el puerto de entrada antes de materializar el aggregate (ej.: `ClaveAcceso` = 49 dígitos rechazada en frontera).
- **Integración entre BCs por eventos:** usa eventos de dominio (Kafka) para integrar contextos. No acoples con llamadas síncronas directas cuando corresponde un evento.
- **CQRS con criterio:** separa lectura/escritura solo donde la asimetría lo justifique. No por defecto.
- **Orquestación determinística:** los flujos se orquestan de forma explícita y determinística. No agentes autónomos decidiendo su plan en runtime.

## Memoria (engram)
- Engram es memoria episódica; la matriz de permisos en `opencode.json` es **autoritativa** (lectura global, escritura por rol). No intentes operaciones denegadas para tu rol.
- Recupera antes de asumir: consulta engram/artefactos en vez de reconstruir de memoria.
- Guarda solo **decisiones durables** (ADRs, invariantes, canónicos). No guardes ruido conversacional ni pasos intermedios.

## Convenciones de código
- **Java/Spring/Quarkus:** inyección por constructor (no por campo). Value objects inmutables. Excepciones de dominio específicas, no genéricas. El dominio no conoce el framework.
- **Python:** dependencias y ejecución con `uv` (nunca `pip` directo ni venvs manuales).
- **Javascript/Typescript:** dependencias y ejecución con pnpm 
- **Tests:** TDD donde aplique (skill `springboot-tdd`). No introduzcas lógica de dominio sin su prueba.

## Entorno y herramientas
- Contenedores: **Podman**, no Docker.
- Exploración de código: `rg`, `fd`, `ast-grep`, `jq`, `yq`. Prefiérelos a reimplementar búsquedas.

## Licenciamiento
- En productos comerciales cerrados, solo dependencias **Apache-2.0 / MIT**. Copyleft fuerte (GPL/AGPL) es **bloqueante**: márcalo y propone alternativa permisiva.

## Disciplina de cambios
- Cambios pequeños y revisables. No rompas fronteras de dominio ni la regla de dependencia "para ir rápido".
- Si una propuesta viola una invariante de arquitectura, **objétala** en vez de ejecutarla; ofrece la alternativa conforme.

## Ramas (GitFlow)
Modelo GitFlow. Los agentes **nunca** hacen commit directo a `main` ni `develop`.
- `main` — producción; siempre desplegable. Solo recibe merges de `release/*` y `hotfix/*`. Cada merge se etiqueta con versión (SemVer).
- `develop` — integración; base de las features.
- `feature/<ticket>-<slug>` — sale de `develop`, vuelve a `develop` vía PR.
- `release/<version>` — sale de `develop`; estabilización; mergea a `main` y `develop`.
- `hotfix/<version>` — sale de `main`; mergea a `main` y `develop`.
- Todo merge a `main`/`develop` es vía Pull Request revisado. Push directo prohibido.
- Un branch = una unidad de trabajo (una story/epic). Commits atómicos.

## Anti-patrones (rechazar)
- Controller/servicio llamando directo al repositorio JPA saltando el dominio.
- Anotaciones o tipos de infraestructura dentro del dominio.
- Parafrasear valores normativos/NFR de memoria sin recuperarlos de la fuente.
- Acoplar bounded contexts con llamadas síncronas donde corresponde un evento.
- Guardar ruido en engram o exceder los permisos de tu rol.
