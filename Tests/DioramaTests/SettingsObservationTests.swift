import Foundation
import Observation
import SwiftUI
import Testing
import os
import DioramaCore
@testable import Diorama

@Suite @MainActor
struct SettingsObservationTests {
    @Test func permissionPaneIgnoresUnrelatedStageChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = fixture.model.accessibilityGranted
            _ = fixture.model.screenRecordingGranted
        } onChange: {
            changed.withLock { $0 = true }
        }

        fixture.model.interactive.toggle()
        fixture.model.resolution = StageResolution.all.last!
        fixture.model.releasePointer()
        #expect(!changed.withLock { $0 })
    }

    @Test func unchangedStateDoesNotInvalidateSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = model.interactive
            _ = model.resolution
            _ = model.captured
            _ = model.displayError
            _ = model.captureError
            _ = model.inputError
        } onChange: {
            changed.withLock { $0 = true }
        }

        let interactive = model.interactive
        let resolution = model.resolution
        model.interactive = interactive
        model.resolution = resolution
        model.releasePointer()
        model.retry()
        #expect(!changed.withLock { $0 })
    }

    @Test func nativeBindingsUpdateAndPersistPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        @Bindable var model = fixture.model
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = model.interactive
        } onChange: {
            changed.withLock { $0 = true }
        }

        $model.interactive.wrappedValue = false
        $model.resolution.wrappedValue = StageResolution.all.last!
        #expect(changed.withLock { $0 })
        let reopened = DioramaModel(defaults: fixture.defaults)
        #expect(!reopened.interactive)
        #expect(reopened.resolution == StageResolution.all.last)
    }
}

@MainActor
private struct Fixture {
    let suite = "Diorama.SettingsTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let model: DioramaModel

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        model = DioramaModel(defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }
}
