import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Lo que la insignia de logro **decide y dice** (3.3), sin renderizarla.
///
/// Es la salida de la decisión D1 del 2026-09-20 aplicada a esta pantalla: XCUITest está
/// descartado, así que la lógica de presentación sale de la vista a funciones puras —el estado de
/// un logro y sus tres textos— y se prueba con la suite que ya existe. Lo que queda para el
/// iPhone es lo que solo se ve renderizando: que la barra se pinte, que VoiceOver lo **lea** y
/// que Reduce Motion no anime. Está en `deferred-work.md` con el resto.
///
/// **Aquí es donde se fija que el grid no desbloquea.** Con 42 km en el historial y sin fila en
/// `achievements.json`, el estado es `locked` con la barra llena: AD-17 deja el desbloqueo en el
/// cierre siguiente, y esta suite es lo que impide que alguien lo "arregle".
@Suite("Insignia de logro · qué estado tiene y qué dice")
struct AchievementBadgeViewTests {

    // MARK: - Soporte

    private static func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private static func record(_ startedAt: String, distanceM: Double) throws -> SessionRecord {
        try SessionRecord(
            id: UUID(),
            startedAt: instant(startedAt),
            endedAt: instant(startedAt),
            stepsMeasured: 0,
            stepsEstimated: 0,
            strideM: 0.655,
            distanceM: distanceM,
            durationS: 0,
            pausesS: 0,
            paceSecPerKm: nil,
            cadenceSpm: 0,
            weather: nil,
            recovered: false
        )
    }

    /// Las claves del catálogo del bundle, no una copia: si una entrada cambiara, esto lo dice.
    private static func definition(_ key: String) -> AchievementDefinition {
        AchievementCatalogFixture.bundled.definition(for: key)!
    }

    private static let spanish = Locale(identifier: "es_ES")

    // MARK: - El estado

    @Test("Con fila y con instante, conseguido: la insignia enseña su fecha")
    func unlockedRowWins() throws {
        let unlock = try AchievementUnlock(key: "first_km", unlockedAt: Self.instant("2026-09-01T08:00:00Z"), progress: 1)

        let status = AchievementStatus.of(
            Self.definition("first_km"),
            unlock: unlock,
            isUnreadable: false,
            sessions: [],
            calendar: Self.calendar()
        )

        #expect(status == .unlocked(at: Self.instant("2026-09-01T08:00:00Z")))
    }

    @Test("Sin fila, bloqueado con el progreso que dé el historial de AHORA")
    func lockedDerivesItsProgress() throws {
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 21_000)]

        let status = AchievementStatus.of(
            Self.definition("marathon_42km"),
            unlock: nil,
            isUnreadable: false,
            sessions: sessions,
            calendar: Self.calendar()
        )

        #expect(status == .locked(AchievementProgress(fraction: 0.5, accumulated: 21_000, threshold: 42_000)))
    }

    @Test("Con 42 km y sin fila, la barra está llena y el logro SIGUE bloqueado: el grid no desbloquea (AD-17)")
    func fullBarStaysLocked() throws {
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 42_000)]

        let status = AchievementStatus.of(
            Self.definition("marathon_42km"),
            unlock: nil,
            isUnreadable: false,
            sessions: sessions,
            calendar: Self.calendar()
        )

        #expect(status == .locked(AchievementProgress(fraction: 1, accumulated: 42_000, threshold: 42_000)))
    }

    @Test("Una fila con progreso y SIN instante sigue bloqueada, y su progreso guardado se ignora")
    func storedProgressIsIgnored() throws {
        // La decisión D1 de la 3.3: el progreso se deriva del historial cada vez, porque guardado
        // sería una caché que borrar una caminata (CAP-15) dejaría mintiendo. Hoy, además, nadie
        // escribe estas filas — y por eso está registrado en `deferred-work.md`.
        let stale = try AchievementUnlock(key: "marathon_42km", unlockedAt: nil, progress: 40_000)
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 21_000)]

        let status = AchievementStatus.of(
            Self.definition("marathon_42km"),
            unlock: stale,
            isUnreadable: false,
            sessions: sessions,
            calendar: Self.calendar()
        )

        #expect(status == .locked(AchievementProgress(fraction: 0.5, accumulated: 21_000, threshold: 42_000)))
    }

    @Test("`weekly_goal` bloqueado se muestra SIN barra, no con un 0 % falso (AD-25)")
    func weeklyGoalHasNoBar() {
        let status = AchievementStatus.of(
            Self.definition("weekly_goal"),
            unlock: nil,
            isUnreadable: false,
            sessions: [],
            calendar: Self.calendar()
        )

        #expect(status == .locked(nil))
    }

    @Test("Con el fichero ilegible no se dice 'bloqueado': no se sabe, y eso es otro estado")
    func unreadableIsItsOwnState() throws {
        // Y manda sobre todo lo demás: aunque quedara una fila en memoria, no representa lo que
        // hay en disco (`StoredFileReadOutcome`).
        let unlock = try AchievementUnlock(key: "first_km", unlockedAt: Self.instant("2026-09-01T08:00:00Z"), progress: 1)

        let status = AchievementStatus.of(
            Self.definition("first_km"),
            unlock: unlock,
            isUnreadable: true,
            sessions: [],
            calendar: Self.calendar()
        )

        #expect(status == .unknown)
    }

    // MARK: - Los textos

    @Test("El progreso se lee en la unidad de su métrica: km, sesiones y días")
    func progressTextSpeaksItsUnit() {
        let distance = AchievementProgress(fraction: 0.5, accumulated: 21_000, threshold: 42_000)
        let count = AchievementProgress(fraction: 0.1, accumulated: 3, threshold: 30)
        let days = AchievementProgress(fraction: 4.0 / 7.0, accumulated: 4, threshold: 7)

        #expect(AchievementBadgeView.progressText(distance, metric: .totalDistanceM, locale: Self.spanish) == "21,00 de 42,00 km")
        #expect(AchievementBadgeView.progressText(count, metric: .sessionCount, locale: Self.spanish) == "3 de 30 sesiones")
        #expect(AchievementBadgeView.progressText(days, metric: .consecutiveDays, locale: Self.spanish) == "4 de 7 días")
    }

    @Test("Las métricas que no se acumulan no tienen texto de progreso que enseñar")
    func progressTextIsAbsentForTheOthers() {
        let any = AchievementProgress(fraction: 0.5, accumulated: 1, threshold: 2)

        for metric in [AchievementMetric.startHourLocal, .weatherCategory, .tempC, .paceSecPerKm, .weeklyGoalMet] {
            #expect(AchievementBadgeView.progressText(any, metric: metric, locale: Self.spanish) == nil, "\(metric) no tiene unidad que leer")
        }
    }

    @Test("VoiceOver: un logro bloqueado DICE que lo está, y lee su progreso cuando lo tiene")
    func spokenValueSaysTheState() {
        let progress = AchievementProgress(fraction: 0.5, accumulated: 21_000, threshold: 42_000)

        let withBar = AchievementBadgeView.spokenValue(
            .locked(progress), metric: .totalDistanceM, calendar: Self.calendar(), locale: Self.spanish
        )
        let withoutBar = AchievementBadgeView.spokenValue(
            .locked(nil), metric: .weeklyGoalMet, calendar: Self.calendar(), locale: Self.spanish
        )

        #expect(withBar == "Bloqueado. 21,00 de 42,00 km")
        #expect(withoutBar == "Bloqueado")
    }

    @Test("VoiceOver: sin poder leer el fichero no se lee 'bloqueado', se lee que no se sabe")
    func spokenValueDoesNotLieWhenUnreadable() {
        let spoken = AchievementBadgeView.spokenValue(
            .unknown, metric: .sessionDistanceM, calendar: Self.calendar(), locale: Self.spanish
        )

        #expect(spoken == "No se pudo leer si lo has conseguido")
        #expect(!spoken.contains("Bloqueado"))
    }

    @Test("VoiceOver: un logro conseguido lee cuándo se ganó")
    func spokenValueOfAnUnlockedBadge() {
        let spoken = AchievementBadgeView.spokenValue(
            .unlocked(at: Self.instant("2026-09-01T08:00:00Z")),
            metric: .sessionDistanceM,
            calendar: Self.calendar(),
            locale: Self.spanish
        )

        #expect(spoken.hasPrefix("Conseguido el "))
        #expect(spoken.contains(AchievementBadgeView.dateText(Self.instant("2026-09-01T08:00:00Z"), calendar: Self.calendar(), locale: Self.spanish)))
    }

    @Test("La fecha de desbloqueo es LOCAL, con el calendario del reloj (AD-19)")
    func unlockedDateIsLocal() {
        // Las 02:00 UTC del 2 de septiembre son las 21:00 del **día 1** en Guayaquil. Sin pasarle
        // la zona del `AppCalendar` al formato, los dos textos saldrían iguales.
        let instant = Self.instant("2026-09-02T02:00:00Z")
        let utc = Self.calendar()
        let guayaquil = Self.calendar("America/Guayaquil")

        let inUtc = AchievementBadgeView.dateText(instant, calendar: utc, locale: Self.spanish)
        let inGuayaquil = AchievementBadgeView.dateText(instant, calendar: guayaquil, locale: Self.spanish)

        #expect(inUtc != inGuayaquil)
        #expect(inUtc.contains("\(utc.component(.day, from: instant))"))
        #expect(inGuayaquil.contains("\(guayaquil.component(.day, from: instant))"))
        #expect(guayaquil.component(.day, from: instant) == 1)
    }
}
