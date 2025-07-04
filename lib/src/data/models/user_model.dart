import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:face_verify/extension/face_from_json.dart';
import 'package:face_verify/extension/face_to_json.dart';
import 'package:face_verify/extension/rect_to_json.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class UserModel extends Equatable {
  final int id;
  final String? image;
  final String name;
  final List<double> embeddings;
  final double distance;

  final Rect? location;

  final Face? face;

  /// Constructs a Category.
  const UserModel(
      {required this.name,
      required this.id,
      this.image,
      this.face,
      this.location,
      required this.embeddings,
      required this.distance});

  UserModel copyWith({
    String? name,
    List<double>? embeddings,
    double? distance,
    int? id,
    String? image,
    Rect? location,
    Face? face,
  }) {
    return UserModel(
      name: name ?? this.name,
      embeddings: embeddings ?? this.embeddings,
      distance: distance ?? this.distance,
      id: id ?? this.id,
      image: image ?? this.image,
      location: location ?? this.location,
      face: face ?? this.face,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
      image: json['image'] as String?,
      embeddings: List<double>.from(json['embeddings'] ?? []),
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      location: json['location'] != null
          ? Rect.fromLTRB(
              (json['location']['left'] as num).toDouble(),
              (json['location']['top'] as num).toDouble(),
              (json['location']['right'] as num).toDouble(),
              (json['location']['bottom'] as num).toDouble(),
            )
          : null,
      face: json['face'] != null ? FaceJsons.fromJson(json['face']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image': image,
      'embeddings': embeddings,
      'distance': distance.isFinite ? distance : null,
      'location': location != null ? RectJsons.toJson(location!) : null,
      'face': face?.toJson(),
    };
  }

  @override
  String toString() {
    return 'UserModel { id: $id, name: $name, image: $image, distance: $distance }';
  }

  @override
  List<Object?> get props => [
        id,
        name,
        image,
        embeddings,
        distance,
        location,
        face,
      ];
}
