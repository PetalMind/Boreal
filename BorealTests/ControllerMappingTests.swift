import CoreGraphics
import Foundation
import Testing
@testable import Boreal

struct ControllerMappingTests {
    @Test func standardMappingCoversMovementAndPrimaryActions() {
        let mapping = ControllerMapping.standard

        #expect(mapping[.leftStickUp] == .w)
        #expect(mapping[.leftStickDown] == .s)
        #expect(mapping[.leftStickLeft] == .a)
        #expect(mapping[.leftStickRight] == .d)
        #expect(mapping[.buttonA] == .space)
        #expect(mapping[.menu] == .returnKey)
    }

    @Test func mappingRoundTripsThroughPersistenceFormat() throws {
        var mapping = ControllerMapping.standard
        mapping[.buttonA] = .e
        mapping[.rightStickUp] = .up
        mapping.stickDeadZone = 0.7

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(ControllerMapping.self, from: data)

        #expect(decoded == mapping)
    }

    @Test func unmappedInputDoesNotProduceAKeyCode() {
        #expect(ControllerKey.none.keyCode == nil)
        #expect(ControllerKey.space.keyCode == CGKeyCode(49))
        #expect(ControllerKey.up.keyCode == CGKeyCode(126))
    }

    @Test func wineEnvironmentEnablesControllerDiscoveryAndBackgroundHotPlug() {
        let environment = ControllerWineSupport.applyingEnvironment(to: ["EXISTING": "value"])

        #expect(environment["SDL_JOYSTICK_HIDAPI"] == "1")
        #expect(environment["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"] == "1")
        #expect(environment["EXISTING"] == "value")
    }

    @Test func legacyCompatibilityProfileGetsSafeControllerDefaults() throws {
        let data = Data(#"{"windowsVersion":"win11","architecture":"win64"}"#.utf8)
        let profile = try JSONDecoder().decode(WineCompatibilityProfile.self, from: data)

        #expect(profile.forceXInput)
        #expect(!profile.disableSteamInputEquivalent)
    }

    @Test func environmentCopiesPerGameXInputPreference() {
        var profile = WineCompatibilityProfile.default
        profile.forceXInput = false

        let configuration = EnvironmentConfiguration(name: "Controller test", profile: profile)

        #expect(!configuration.forceXInput)
    }
}
