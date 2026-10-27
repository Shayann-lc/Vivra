import GRDB

/// Schema migrations, applied in order. Each step is append-only: never edit
/// a shipped migration, add a new one.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_settings") { db in
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_health") { db in
            // Times are Unix timestamps (REAL) so HealthKit dates round-trip
            // exactly. Ids are HealthKit object UUIDs.
            try db.create(table: "quantity_sample") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("value", .double).notNull()
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "quantity_sample_kind_start", on: "quantity_sample", columns: ["kind", "start"])

            try db.create(table: "sleep_interval") { t in
                t.primaryKey("id", .text)
                t.column("stage", .text).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "sleep_interval_end", on: "sleep_interval", columns: ["end"])

            try db.create(table: "workout") { t in
                t.primaryKey("id", .text)
                t.column("activity_type", .integer).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("duration", .double).notNull()
                t.column("active_energy_kcal", .double)
                t.column("distance_m", .double)
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "workout_start", on: "workout", columns: ["start"])

            try db.create(table: "sync_anchor") { t in
                t.primaryKey("data_type", .text)
                t.column("anchor", .blob).notNull()
            }

            try db.create(table: "report") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("period_start", .text).notNull()
                t.column("period_end", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("generator", .text).notNull()
                t.column("summary_json", .blob).notNull()
            }
        }

        migrator.registerMigration("v3_phase2") { db in
            try db.create(table: "category_event") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("value", .integer).notNull()
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "category_event_kind_start", on: "category_event", columns: ["kind", "start"])

            try db.create(table: "state_of_mind") { t in
                t.primaryKey("id", .text)
                t.column("date", .double).notNull()
                t.column("kind", .text).notNull()
                t.column("valence", .double).notNull()
                // Comma-separated HKStateOfMind label and association raw values.
                t.column("labels", .text).notNull()
                t.column("associations", .text).notNull()
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "state_of_mind_date", on: "state_of_mind", columns: ["date"])

            try db.create(table: "ecg_record") { t in
                t.primaryKey("id", .text)
                t.column("date", .double).notNull()
                t.column("classification", .text).notNull()
                t.column("source_bundle_id", .text).notNull()
                t.column("source_name", .text).notNull()
            }
            try db.create(index: "ecg_record_date", on: "ecg_record", columns: ["date"])

            try db.create(table: "log_entry") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("timestamp", .double).notNull()
                t.column("scale", .integer)
                t.column("drink", .text)
                t.column("amount", .double)
                t.column("note", .text)
                t.column("healthkit_sample_id", .text)
            }
            try db.create(index: "log_entry_timestamp", on: "log_entry", columns: ["timestamp"])

            try db.alter(table: "report") { t in
                t.add(column: "kind", .text).notNull().defaults(to: "weekly")
            }
        }

        migrator.registerMigration("v4_progress") { db in
            try db.create(table: "goal_setting") { t in
                t.primaryKey("effective_day", .text)
                t.column("target", .integer).notNull()
            }
            // Append-only: rows are never updated or deleted (except by
            // "delete everything").
            try db.create(table: "app_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("date", .double).notNull()
            }
        }

        return migrator
    }
}
