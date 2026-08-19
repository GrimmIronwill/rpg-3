@tool
class_name DBEntryExport
extends Resource

@export var table_name: String = ""
@export var schema_name: String = ""
@export var schema: DBSchema = null
@export var entry: DBEntry = null

static func from_entry(table: DBTable, source_entry: DBEntry) -> DBEntryExport:
	var out := DBEntryExport.new()

	if table:
		out.table_name = table.table_name
		out.schema = table.schema.duplicate(true) as DBSchema if table.schema else null
		out.schema_name = table.schema.schema_name if table.schema else ""

	if source_entry:
		out.entry = source_entry.duplicate(true) as DBEntry
		if out.schema_name.is_empty():
			out.schema_name = source_entry.schema_name

	return out
