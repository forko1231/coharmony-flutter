import 'package:flutter/material.dart';

/// Shared value types for the custody day/override editors. Ports of the small
/// classes in `Views/Schedule/DayEditorView.xaml.cs`, `OverrideEditorView.xaml.cs`,
/// `OverrideDayEditResult.cs`, and the `LocationData` struct from `CustodySchedule`.
///
/// Times use [TimeOfDay] (MAUI used `TimeSpan`); the page formats them to "HH:mm"
/// strings for the DTOs. [TimeOfDay] has value equality, so baseline diffing works.

/// Handoff location selected in an editor (mirrors MAUI's `LocationData` struct).
class LocationData {
  const LocationData(this.latitude, this.longitude, this.name, this.address);
  final double? latitude;
  final double? longitude;
  final String? name;
  final String? address;
}

/// Pre-edit baseline for a day (active proposal's prior version, else approved
/// schedule), so the editor can show per-field "was X · Revert".
class DayBaseline {
  DayBaseline({this.parent = 'None', this.time, this.endTime, this.locName, this.locAddr});
  final String parent;
  final TimeOfDay? time;
  final TimeOfDay? endTime;
  final String? locName;
  final String? locAddr;
}

/// Payload reported by the day editor whenever the user changes something.
class DayEditCommit {
  const DayEditCommit({
    required this.weekIndex,
    required this.dayIndex,
    required this.parent,
    this.transferTime,
    this.transferEndTime,
    this.location,
    required this.recolor,
  });
  final int weekIndex;
  final int dayIndex;
  final String parent; // "Husband" | "Wife" | "Both" | "None"
  final TimeOfDay? transferTime;
  final TimeOfDay? transferEndTime;
  final LocationData? location;

  /// True for discrete edits (parent/toggles) that should recolor the cell now.
  final bool recolor;
}

/// Pre-edit baseline for a special day (the approved-schedule override). Null when
/// adding a brand-new override (nothing to diff against).
class OverrideBaseline {
  OverrideBaseline(
      {this.parent = 'None', this.time, this.endTime, this.locName, this.locAddr});
  final String parent;
  final TimeOfDay? time;
  final TimeOfDay? endTime;
  final String? locName;
  final String? locAddr;
}

/// Result of editing an override (special) day — produced by the override editor's
/// Add/Update button, consumed by the page's `handleOverrideDayEditResult`.
class OverrideDayEditResult {
  const OverrideDayEditResult({
    required this.dateKey,
    this.originalDateKey,
    required this.selectedDate,
    required this.parent,
    this.transferTime,
    this.transferEndTime,
    this.description = '',
    this.isAnnual = false,
    this.alternationMode = 'fixed',
    this.alternationStartParent,
    this.transferLocation,
    this.holidayRule,
    this.wasCancelled = false,
  });

  final String dateKey;

  /// Original date key when editing an existing override — tracks date changes.
  final String? originalDateKey;
  final DateTime selectedDate;
  final String parent;
  final TimeOfDay? transferTime;
  final TimeOfDay? transferEndTime;
  final String description;
  final bool isAnnual;
  final String alternationMode;
  final String? alternationStartParent;
  final LocationData? transferLocation;
  final String? holidayRule;
  final bool wasCancelled;

  /// True if the date was changed from the original.
  bool get dateWasChanged => originalDateKey != null && originalDateKey != dateKey;
}
