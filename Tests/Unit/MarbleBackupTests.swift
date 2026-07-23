import SwiftData
import XCTest
@testable import marble

@MainActor
final class MarbleBackupTests: MarbleTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "persistenceLastSuccessfulRestore")
        super.tearDown()
    }

    func testBackupRoundTripRestoresCoreTrainingDataAndRelationships() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "150m Sprints", category: .run, preferredDistanceUnit: .meters, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 150, durationSeconds: 20, restAfterSeconds: 180)
        let session = WorkoutSession(title: "Pull", startedAt: now.addingTimeInterval(-1200), endedAt: now, entries: [entry])
        let type = SupplementType(name: "Creatine", defaultDose: 5, unit: .g, isFavorite: true)
        let supplement = SupplementEntry(type: type, takenAt: now, dose: 5, unit: .g)
        source.insert(exercise)
        source.insert(entry)
        source.insert(session)
        source.insert(type)
        source.insert(supplement)
        source.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        source.insert(SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 2,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        try source.save()

        let document = try MarbleBackupService.makeDocument(in: source, now: now)
        let summary = try MarbleBackupService.inspect(data: document.data)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.supplementLogs, 1)

        let destination = makeInMemoryContext()
        let firstRestore = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(firstRestore.sets, 1)
        XCTAssertEqual(firstRestore.sessions, 1)

        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SupplementEntry>()), 1)
        let restoredSprint = try XCTUnwrap(destination.fetch(FetchDescriptor<SprintPrescription>()).first)
        XCTAssertEqual(restoredSprint.distance, 150)
        XCTAssertEqual(restoredSprint.repetitionCount, 4)
        XCTAssertEqual(restoredSprint.targetLowerSeconds, 19)
        XCTAssertEqual(restoredSprint.targetUpperSeconds, 21)
        let restoredGoal = try XCTUnwrap(destination.fetch(FetchDescriptor<SprintGoalSnapshot>()).first)
        XCTAssertEqual(restoredGoal.setEntryID, entry.id)
        XCTAssertEqual(restoredGoal.repetitionNumber, 2)
        XCTAssertEqual(restoredGoal.plan, SprintPrescriptionPlan(
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        let restoredSession = try XCTUnwrap(destination.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restoredSession.entries.first?.exercise.name, "150m Sprints")

        let secondRestore = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(secondRestore.sets, 0)
        XCTAssertEqual(secondRestore.sessions, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 1, "merge restore must be idempotent")
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 1)
    }

    // MARK: - Bodyweight history

    /// Months of weigh-ins used to vanish on a phone-to-phone restore:
    /// `BodyMetricEntry` was never fetched, never in the payload, never
    /// restored. The Trends bodyweight chart fell back to its empty state and
    /// DOTS relative strength disappeared, with nothing on screen to say why.
    func testBackupRoundTripPreservesBodyMetrics() throws {
        let source = makeInMemoryContext()
        let older = BodyMetricEntry(
            measuredAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
            weightKilograms: 84.5,
            bodyFatPercent: 18.2,
            source: .manual,
            notes: "Morning, fasted"
        )
        let healthKitUUID = UUID()
        let newer = BodyMetricEntry(
            measuredAt: now,
            weightKilograms: 82.1,
            source: .healthKit,
            healthKitUUID: healthKitUUID
        )
        source.insert(older)
        source.insert(newer)
        try source.save()

        let document = try MarbleBackupService.makeDocument(in: source, now: now)
        XCTAssertEqual(try MarbleBackupService.inspect(data: document.data).bodyMetrics, 2)

        let destination = makeInMemoryContext()
        let restored = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(restored.bodyMetrics, 2)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<BodyMetricEntry>()), 2)

        let entries = try destination.fetch(FetchDescriptor<BodyMetricEntry>())
            .sorted { $0.measuredAt < $1.measuredAt }
        // Kilograms are canonical and must survive the file untouched.
        XCTAssertEqual(entries[0].weightKilograms, 84.5, accuracy: 0.0001)
        XCTAssertEqual(entries[0].bodyFatPercent ?? .nan, 18.2, accuracy: 0.0001)
        XCTAssertEqual(entries[0].source, .manual)
        XCTAssertEqual(entries[0].notes, "Morning, fasted")
        XCTAssertNil(entries[0].healthKitUUID)
        XCTAssertEqual(entries[1].weightKilograms, 82.1, accuracy: 0.0001)
        XCTAssertNil(entries[1].bodyFatPercent)
        XCTAssertEqual(entries[1].source, .healthKit)
        // Kept so a re-import from Health can still dedup after a restore.
        XCTAssertEqual(entries[1].healthKitUUID, healthKitUUID)
        XCTAssertEqual(entries[0].id, older.id)
        XCTAssertEqual(entries[1].id, newer.id)
    }

    func testRestoringBodyMetricsTwiceIsIdempotent() throws {
        let source = makeInMemoryContext()
        source.insert(BodyMetricEntry(measuredAt: now, weightKilograms: 80))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        let destination = makeInMemoryContext()
        XCTAssertEqual(try MarbleBackupService.restore(data: document.data, into: destination).bodyMetrics, 1)

        let second = try MarbleBackupService.restore(data: document.data, into: destination)

        XCTAssertEqual(second.bodyMetrics, 0)
        XCTAssertEqual(
            try destination.fetchCount(FetchDescriptor<BodyMetricEntry>()),
            1,
            "id is @Attribute(.unique) — a second restore must merge, not upsert"
        )
    }

    /// `bodyMetrics` is optional precisely so `formatVersion` can stay at 1:
    /// every backup file exported before 2.2 must still restore.
    func testLegacyBackupWithoutBodyMetricsStillRestores() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Legacy Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        source.insert(exercise)
        source.insert(SetEntry(exercise: exercise, performedAt: now, weight: 100, reps: 5, restAfterSeconds: 120))
        source.insert(BodyMetricEntry(measuredAt: now, weightKilograms: 80))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "bodyMetrics")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(try MarbleBackupService.inspect(data: legacyData).bodyMetrics, 0)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.bodyMetrics, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
    }

    func testRestoreRejectsNonPositiveBodyweightBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        source.insert(exercise)
        source.insert(BodyMetricEntry(measuredAt: now, weightKilograms: 80))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["bodyMetrics"] as? [[String: Any]])
        records[0]["weightKilograms"] = 0
        json["bodyMetrics"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
    }

    func testRestoreRejectsDuplicateBodyMetricIDsBeforeMutation() throws {
        let source = makeInMemoryContext()
        source.insert(BodyMetricEntry(measuredAt: now, weightKilograms: 80))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        let records = try XCTUnwrap(json["bodyMetrics"] as? [[String: Any]])
        json["bodyMetrics"] = records + records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<BodyMetricEntry>()), 0)
    }

    func testRestoreRepairsMissingSetRelationshipOnExistingSession() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let entry = SetEntry(exercise: exercise, performedAt: now, weight: 225, reps: 5, restAfterSeconds: 120)
        let session = WorkoutSession(title: "Legs", startedAt: now.addingTimeInterval(-900), endedAt: now, entries: [entry])
        source.insert(exercise)
        source.insert(entry)
        source.insert(session)
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        let destination = makeInMemoryContext()
        let existingExercise = Exercise(id: exercise.id, name: exercise.name, category: exercise.category, metrics: exercise.metrics, defaultRestSeconds: 120)
        let existingSession = WorkoutSession(id: session.id, title: session.title, startedAt: session.startedAt, endedAt: session.endedAt)
        destination.insert(existingExercise)
        destination.insert(existingSession)
        try destination.save()

        let restored = try MarbleBackupService.restore(data: document.data, into: destination)

        XCTAssertEqual(restored.sets, 1)
        XCTAssertEqual(restored.sessions, 0)
        XCTAssertEqual(existingSession.entries.map { $0.id }, [entry.id])
    }

    func testRejectsInvalidBackupBeforeMutation() throws {
        let context = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: Data("not-json".utf8), into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 0)
    }

    func testLegacyBackupWithoutSprintPrescriptionsStillRestores() throws {
        let source = makeInMemoryContext()
        source.insert(Exercise(name: "Legacy Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "sprintPrescriptions")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.exercises, 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
    }

    func testLegacyBackupWithoutSprintGoalSnapshotsStillRestores() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Legacy Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        source.insert(exercise)
        source.insert(SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "sprintGoalSnapshots")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }

    func testRestoreRejectsInvalidSprintPrescriptionBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        source.insert(exercise)
        source.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["sprintPrescriptions"] as? [[String: Any]])
        records[0]["distance"] = 0
        json["sprintPrescriptions"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintPrescription>()), 0)
    }

    func testRestoreRejectsSprintGoalSnapshotReferencingMissingSetBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Sprint", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 180)
        let entry = SetEntry(
            exercise: exercise,
            performedAt: now,
            distance: 150,
            durationSeconds: 20,
            restAfterSeconds: 180
        )
        source.insert(exercise)
        source.insert(entry)
        source.insert(SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 1,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["sprintGoalSnapshots"] as? [[String: Any]])
        records[0]["setEntryID"] = UUID().uuidString
        json["sprintGoalSnapshots"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SprintGoalSnapshot>()), 0)
    }

    // MARK: - Payload exhaustiveness guard

    /// Fails the moment a new `@Model` joins the schema without joining the
    /// backup payload. `makeDocument` hand-lists every entity, and that list
    /// has silently lost data twice (`ImportedWorkout` once, `BodyMetricEntry`
    /// once) — this test makes the third time a build failure instead of a
    /// data loss. The current schema's `models` array is the source of truth.
    func testBackupPayloadCoversEveryModelInCurrentSchema() throws {
        // One instance of every entity in the schema, so an exported array
        // that stays empty can only mean makeDocument never fetched it.
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Squat", category: .legs, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        let entry = SetEntry(exercise: exercise, performedAt: now, weight: 100, reps: 5, restAfterSeconds: 120)
        let type = SupplementType(name: "Creatine", defaultDose: 5, unit: .g, isFavorite: true)
        source.insert(exercise)
        source.insert(entry)
        source.insert(WorkoutSession(title: "Legs", startedAt: now.addingTimeInterval(-900), endedAt: now, entries: [entry]))
        source.insert(type)
        source.insert(SupplementEntry(type: type, takenAt: now, dose: 5, unit: .g))
        let plan = SplitPlan(name: "PPL")
        let day = SplitDay(weekday: .monday, title: "Push", order: 0, plan: plan)
        day.plannedSets = [PlannedSet(order: 0, exercise: exercise, day: day)]
        plan.days = [day]
        source.insert(plan)
        source.insert(SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        source.insert(SprintGoalSnapshot(
            setEntryID: entry.id,
            exerciseID: exercise.id,
            distance: 150,
            distanceUnit: .meters,
            repetitionNumber: 1,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        ))
        source.insert(BodyMetricEntry(measuredAt: now, weightKilograms: 80))
        let imported = ImportedWorkout(source: .appleHealth, externalID: "hk-guard", title: "Imported", workoutDate: now, setsImported: 1, importedAt: now)
        source.insert(imported)
        entry.importedWorkout = imported
        source.insert(ProgressMediaAttachment(attachedToDate: now, kind: .photo, originalFilename: "guard.jpg"))
        source.insert(CustomNotification(message: "Train"))
        try source.save()

        let document = try MarbleBackupService.makeDocument(in: source, now: now)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        func records(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
        let dayRecords = records("plans").flatMap { $0["days"] as? [[String: Any]] ?? [] }
        let plannedSetRecords = dayRecords.flatMap { $0["plannedSets"] as? [[String: Any]] ?? [] }

        // Where each @Model lives in the JSON. ADDING A MODEL? Export it in
        // `MarbleBackupService.makeDocument`, validate + restore it, seed one
        // instance above, and add its payload location here — this map and the
        // schema must always cover exactly the same set of entities.
        let payloadCounts: [String: Int] = [
            "Exercise": records("exercises").count,
            "SetEntry": records("sets").count,
            "SupplementType": records("supplementTypes").count,
            "SupplementEntry": records("supplementEntries").count,
            "WorkoutSession": records("sessions").count,
            "SplitPlan": records("plans").count,
            "SplitDay": dayRecords.count,
            "PlannedSet": plannedSetRecords.count,
            "SprintPrescription": records("sprintPrescriptions").count,
            "SprintGoalSnapshot": records("sprintGoalSnapshots").count,
            "BodyMetricEntry": records("bodyMetrics").count,
            "ImportedWorkout": records("importedWorkouts").count,
            "ProgressMediaAttachment": records("progressMedia").count,
            "CustomNotification": records("customNotifications").count
        ]

        // `schemas.last`, not a hardcoded version, so bumping to V6 without
        // revisiting the backup fails here too.
        let currentSchema = try XCTUnwrap(MarbleMigrationPlan.schemas.last)
        // `.map { }`, not a key path — key paths do not resolve on metatype
        // existentials (see AGENTS.md, the 2.2 compile trap).
        let schemaModelNames = Set(currentSchema.models.map { String(describing: $0) })
        XCTAssertEqual(
            schemaModelNames,
            Set(payloadCounts.keys),
            "Every @Model in the current schema needs a home in the backup payload — this exact omission has lost user data twice"
        )
        for (model, count) in payloadCounts {
            XCTAssertGreaterThan(count, 0, "\(model) was seeded above but its payload array is empty — makeDocument is not exporting it")
        }
        // Hardcoded on purpose: adding entity #15 must fail here even if the
        // seeding and the map above are both forgotten. When adding a model,
        // update BOTH the backup (makeDocument / validate / restore) AND this
        // test — the count, the map, and the seeded instance.
        XCTAssertEqual(currentSchema.models.count, 14)
    }

    // MARK: - Import ledger, progress media metadata, custom notifications

    /// The import ledger was dropped from the payload once before: after that
    /// restore every re-import created duplicate journal entries because the
    /// dedup ledger came back empty. Media metadata and reminder schedules
    /// were never in the payload at all.
    func testBackupRoundTripPreservesImportLedgerMediaMetadataAndNotifications() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Outdoor Run", category: .run, preferredDistanceUnit: .kilometers, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 5, distanceUnit: .kilometers, durationSeconds: 1500, restAfterSeconds: 0)
        source.insert(exercise)
        source.insert(entry)
        let imported = ImportedWorkout(
            source: .garminConnect,
            externalID: "garmin-123",
            title: "Morning Run",
            workoutDate: now,
            setsImported: 1,
            importedAt: now,
            kind: .running,
            originName: "Garmin",
            sourceAppName: "Garmin Connect",
            deviceName: "Forerunner 265",
            distanceMeters: 5000,
            durationSeconds: 1500,
            calories: 400,
            averageHeartRate: 151,
            maxHeartRate: 175,
            elevationAscendedMeters: 42,
            isIndoor: false
        )
        source.insert(imported)
        entry.importedWorkout = imported
        source.insert(ProgressMediaAttachment(
            attachedToDate: now,
            kind: .photo,
            originalFilename: "2025-01-15-front.jpg",
            thumbnailFilename: "2025-01-15-front-thumb.jpg",
            photoCrop: ProgressPhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
            fileSizeBytes: 123_456
        ))
        let weekdays: Set<Weekday> = [.monday, .thursday]
        source.insert(CustomNotification(message: "Evening session", hour: 18, minute: 30, weekdayMask: CustomNotification.mask(for: weekdays)))
        try source.save()

        let document = try MarbleBackupService.makeDocument(in: source, now: now)
        let summary = try MarbleBackupService.inspect(data: document.data)
        XCTAssertEqual(summary.importedWorkouts, 1)
        XCTAssertEqual(summary.progressMedia, 1)
        XCTAssertEqual(summary.customNotifications, 1)

        let destination = makeInMemoryContext()
        let restored = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(restored.importedWorkouts, 1)
        XCTAssertEqual(restored.progressMedia, 1)
        XCTAssertEqual(restored.customNotifications, 1)

        let restoredImport = try XCTUnwrap(destination.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(restoredImport.id, imported.id)
        // The unique key must survive verbatim — it is what stops a re-import
        // of the same Garmin workout from duplicating the journal.
        XCTAssertEqual(restoredImport.deduplicationKey, "garminConnect:garmin-123")
        XCTAssertEqual(restoredImport.source, .garminConnect)
        XCTAssertEqual(restoredImport.kind, .running)
        XCTAssertEqual(restoredImport.originName, "Garmin")
        XCTAssertEqual(restoredImport.deviceName, "Forerunner 265")
        XCTAssertEqual(restoredImport.distanceMeters ?? .nan, 5000, accuracy: 0.0001)
        XCTAssertEqual(restoredImport.isIndoor, false)
        // The SetEntry↔ImportedWorkout relationship is rebuilt from entryIDs.
        XCTAssertEqual(restoredImport.entries.map(\.id), [entry.id])
        let restoredEntry = try XCTUnwrap(destination.fetch(FetchDescriptor<SetEntry>()).first)
        XCTAssertEqual(restoredEntry.importedWorkout?.id, imported.id)

        // Metadata round-trips; the binary never does (it is not in the JSON).
        let restoredMedia = try XCTUnwrap(destination.fetch(FetchDescriptor<ProgressMediaAttachment>()).first)
        XCTAssertEqual(restoredMedia.kind, .photo)
        XCTAssertEqual(restoredMedia.originalFilename, "2025-01-15-front.jpg")
        XCTAssertEqual(restoredMedia.thumbnailFilename, "2025-01-15-front-thumb.jpg")
        XCTAssertEqual(restoredMedia.photoCrop, ProgressPhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        XCTAssertEqual(restoredMedia.fileSizeBytes, 123_456)

        let restoredNotification = try XCTUnwrap(destination.fetch(FetchDescriptor<CustomNotification>()).first)
        XCTAssertEqual(restoredNotification.message, "Evening session")
        XCTAssertEqual(restoredNotification.hour, 18)
        XCTAssertEqual(restoredNotification.minute, 30)
        XCTAssertEqual(restoredNotification.weekdayMask, CustomNotification.mask(for: weekdays))
        XCTAssertTrue(restoredNotification.isEnabled)
    }

    func testRestoringNewEntityArraysTwiceIsIdempotent() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Treadmill Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 3000, durationSeconds: 900, restAfterSeconds: 0)
        let imported = ImportedWorkout(source: .strava, externalID: "strava-42", title: "Tempo", workoutDate: now, setsImported: 1, importedAt: now)
        source.insert(exercise)
        source.insert(entry)
        source.insert(imported)
        entry.importedWorkout = imported
        source.insert(ProgressMediaAttachment(attachedToDate: now, kind: .video, originalFilename: "check-in.mov"))
        source.insert(CustomNotification(message: "Stretch"))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        let destination = makeInMemoryContext()
        let first = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(first.importedWorkouts, 1)
        XCTAssertEqual(first.progressMedia, 1)
        XCTAssertEqual(first.customNotifications, 1)

        // Both `id` and `deduplicationKey` are @Attribute(.unique) on the
        // ledger — a second restore must merge past them, not upsert or trap.
        let second = try MarbleBackupService.restore(data: document.data, into: destination)
        XCTAssertEqual(second.importedWorkouts, 0)
        XCTAssertEqual(second.progressMedia, 0)
        XCTAssertEqual(second.customNotifications, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ImportedWorkout>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ProgressMediaAttachment>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<CustomNotification>()), 1)
        let restoredImport = try XCTUnwrap(destination.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(restoredImport.entries.map(\.id), [entry.id])
    }

    /// The same Garmin/Strava/Health workout imported independently on two
    /// phones has two different row UUIDs but the identical unique
    /// deduplicationKey. Inserting the incoming id anyway would make SwiftData
    /// upsert over the user's existing ledger row on the key collision.
    func testRestoreSkipsImportedWorkoutWhoseDeduplicationKeyAlreadyExists() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Trail Run", category: .run, metrics: .distanceAndDurationRequired, defaultRestSeconds: 0)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 8000, durationSeconds: 2400, restAfterSeconds: 0)
        let imported = ImportedWorkout(source: .appleHealth, externalID: "hk-shared", title: "Trail", workoutDate: now, setsImported: 1, importedAt: now)
        source.insert(exercise)
        source.insert(entry)
        source.insert(imported)
        entry.importedWorkout = imported
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        let destination = makeInMemoryContext()
        let preexisting = ImportedWorkout(source: .appleHealth, externalID: "hk-shared", title: "Trail", workoutDate: now, setsImported: 1, importedAt: now)
        destination.insert(preexisting)
        try destination.save()
        XCTAssertNotEqual(preexisting.id, imported.id, "the collision under test is key-only")

        let restored = try MarbleBackupService.restore(data: document.data, into: destination)

        XCTAssertEqual(restored.importedWorkouts, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ImportedWorkout>()), 1)
        let survivor = try XCTUnwrap(destination.fetch(FetchDescriptor<ImportedWorkout>()).first)
        XCTAssertEqual(survivor.id, preexisting.id, "the existing ledger row must win, not be upserted over")
        // The restored entry is adopted by the existing row — same repair
        // semantics as sessions.
        XCTAssertEqual(survivor.entries.map(\.id), [entry.id])
    }

    /// The three arrays are optional precisely so `formatVersion` can stay at
    /// 1: every backup file exported before they existed must still restore.
    func testLegacyBackupWithoutImportMediaOrNotificationArraysStillRestores() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Legacy Bench", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 120)
        source.insert(exercise)
        source.insert(SetEntry(exercise: exercise, performedAt: now, weight: 80, reps: 8, restAfterSeconds: 120))
        source.insert(ImportedWorkout(source: .appleHealth, externalID: "hk-legacy", title: "Legacy", workoutDate: now, setsImported: 0, importedAt: now))
        source.insert(ProgressMediaAttachment(attachedToDate: now, kind: .photo, originalFilename: "legacy.jpg"))
        source.insert(CustomNotification(message: "Legacy reminder"))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        json.removeValue(forKey: "importedWorkouts")
        json.removeValue(forKey: "progressMedia")
        json.removeValue(forKey: "customNotifications")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let legacySummary = try MarbleBackupService.inspect(data: legacyData)
        XCTAssertEqual(legacySummary.importedWorkouts, 0)
        XCTAssertEqual(legacySummary.progressMedia, 0)
        XCTAssertEqual(legacySummary.customNotifications, 0)

        let destination = makeInMemoryContext()
        let summary = try MarbleBackupService.restore(data: legacyData, into: destination)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.importedWorkouts, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ImportedWorkout>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ProgressMediaAttachment>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<CustomNotification>()), 0)
    }

    func testRestoreRejectsImportedWorkoutReferencingMissingSetBeforeMutation() throws {
        let source = makeInMemoryContext()
        let exercise = Exercise(name: "Row", category: .back, metrics: .distanceAndDurationRequired, defaultRestSeconds: 60)
        let entry = SetEntry(exercise: exercise, performedAt: now, distance: 2000, durationSeconds: 480, restAfterSeconds: 60)
        let imported = ImportedWorkout(source: .appleHealth, externalID: "hk-row", title: "Row", workoutDate: now, setsImported: 1, importedAt: now)
        source.insert(exercise)
        source.insert(entry)
        source.insert(imported)
        entry.importedWorkout = imported
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["importedWorkouts"] as? [[String: Any]])
        records[0]["entryIDs"] = [UUID().uuidString]
        json["importedWorkouts"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SetEntry>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ImportedWorkout>()), 0)
    }

    /// A key that no longer matches "<source>:<externalID>" would make the
    /// dedup-on-restore and the database's unique constraint disagree about
    /// which rows are "the same" workout, so it is rejected up front.
    func testRestoreRejectsImportedWorkoutWithMismatchedDeduplicationKeyBeforeMutation() throws {
        let source = makeInMemoryContext()
        source.insert(ImportedWorkout(source: .strava, externalID: "strava-7", title: "Ride", workoutDate: now, setsImported: 0, importedAt: now))
        try source.save()
        let document = try MarbleBackupService.makeDocument(in: source, now: now)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.data) as? [String: Any])
        var records = try XCTUnwrap(json["importedWorkouts"] as? [[String: Any]])
        records[0]["deduplicationKey"] = "strava:some-other-id"
        json["importedWorkouts"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: json)

        let destination = makeInMemoryContext()
        XCTAssertThrowsError(try MarbleBackupService.restore(data: invalidData, into: destination))
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<ImportedWorkout>()), 0)
    }
}
