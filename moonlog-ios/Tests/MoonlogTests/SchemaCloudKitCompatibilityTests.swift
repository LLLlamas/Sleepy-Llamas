import XCTest
import SwiftData
@testable import Moonlog

/// Asserts the schema mechanically, so the moment someone adds a property that
/// CloudKit cannot mirror, this fails — instead of surfacing months later as a
/// store that silently refuses to open and an app that shows "no data" while new
/// records vanish on relaunch.
///
/// Every rule here was verified against this machine's SDK by loading a
/// deliberately-invalid model and reading the rejection back.
final class SchemaCloudKitCompatibilityTests: XCTestCase {

    private var entities: [Schema.Entity] { ModelContainerFactory.schema.entities }

    /// Names, not a count — this also catches a model quietly dropped from the
    /// schema, which would silently stop it syncing.
    func testEveryModelIsRegistered() {
        XCTAssertEqual(
            Set(entities.map(\.name)),
            ["Family", "Baby", "Shift", "LogEvent", "SleepSession",
             "NoteTagPreset", "TagBinding"])
    }

    /// "CloudKit integration does not support unique constraints."
    func testNoUniquenessConstraints() {
        for entity in entities {
            XCTAssertTrue(
                entity.uniquenessConstraints.isEmpty,
                "\(entity.name): CloudKit cannot enforce unique constraints")
        }
    }

    /// "CloudKit integration requires that all attributes be optional, or have a
    /// default value set." Verified: assigning in `init` does NOT satisfy this —
    /// only an inline property initialiser populates `defaultValue`.
    func testEveryAttributeIsOptionalOrHasAnInlineDefault() {
        for entity in entities {
            for attribute in entity.attributes {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) must be optional or carry an "
                        + "INLINE default — a value assigned in init is not enough")
            }
        }
    }

    func testNoAttributeIsMarkedUnique() {
        for entity in entities {
            for attribute in entity.attributes {
                XCTAssertFalse(
                    attribute.isUnique,
                    "\(entity.name).\(attribute.name): .unique is unsupported under CloudKit")
            }
        }
    }

    /// "CloudKit requires all relationships to be optional."
    func testEveryRelationshipIsOptional() {
        for entity in entities {
            for relationship in entity.relationships {
                XCTAssertTrue(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) must be optional")
            }
        }
    }

    /// "The following relationships are configured with unsupported delete rules."
    /// `.deny` is rejected; `.cascade` is accepted — verified directly, and note
    /// this contradicts the comment in The-Llamas-Cookbook, which says cascade is
    /// rejected. It is not.
    func testNoRelationshipUsesDenyDeleteRule() {
        for entity in entities {
            for relationship in entity.relationships {
                XCTAssertNotEqual(
                    relationship.deleteRule, .deny,
                    "\(entity.name).\(relationship.name): CloudKit rejects .deny")
            }
        }
    }
}
