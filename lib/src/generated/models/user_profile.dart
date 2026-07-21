// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'user_profile.g.dart';

@JsonSerializable()
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.displayName,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);

  final String id;
  final String email;
  final String? displayName;

  Map<String, Object?> toJson() => _$UserProfileToJson(this);
}
