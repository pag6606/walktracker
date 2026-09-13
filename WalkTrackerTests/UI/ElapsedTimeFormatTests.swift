import Foundation
import Testing

@testable import WalkTracker

@Suite("Formato del cronómetro")
struct ElapsedTimeFormatTests {

    @Test("m:ss por debajo de una hora, h:mm:ss a partir de ella, truncando al segundo")
    func clockText() {
        #expect(ElapsedTimeFormat.clock(0) == "0:00")
        #expect(ElapsedTimeFormat.clock(0.99) == "0:00")
        #expect(ElapsedTimeFormat.clock(1) == "0:01")
        #expect(ElapsedTimeFormat.clock(65) == "1:05")
        #expect(ElapsedTimeFormat.clock(3599.5) == "59:59")
        #expect(ElapsedTimeFormat.clock(3600) == "1:00:00")
        #expect(ElapsedTimeFormat.clock(3725) == "1:02:05")
        #expect(ElapsedTimeFormat.clock(-5) == "0:00")
        #expect(ElapsedTimeFormat.clock(.nan) == "0:00")
    }

    @Test("La lectura de VoiceOver trunca al segundo y nunca es negativa")
    func spokenTruncates() {
        let es = Locale(identifier: "es_ES")
        #expect(ElapsedTimeFormat.spoken(59.9, locale: es) == ElapsedTimeFormat.spoken(59, locale: es))
        #expect(ElapsedTimeFormat.spoken(-5, locale: es) == ElapsedTimeFormat.spoken(0, locale: es))
        #expect(ElapsedTimeFormat.spoken(.nan, locale: es) == ElapsedTimeFormat.spoken(0, locale: es))
    }

    @Test("La lectura de VoiceOver dice horas, minutos y segundos en español")
    func spokenSpanish() {
        #expect(ElapsedTimeFormat.spoken(3725, locale: Locale(identifier: "es_ES")) == "1 hora, 2 minutos y 5 segundos")
    }
}
