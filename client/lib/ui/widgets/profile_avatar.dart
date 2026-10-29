import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';
import 'net_image.dart';

/// A profile picture: the uploaded photo, or the emoji on the profile colour.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final String color;
  final String avatar;
  final String photo;

  /// A just-picked photo that is not uploaded yet (edit dialog preview).
  final Uint8List? localPhoto;
  final double size;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.name,
    required this.color,
    required this.avatar,
    this.photo = '',
    this.localPhoto,
    required this.size,
    required this.radius,
  });

  ProfileAvatar.of(
    Profile? p, {
    super.key,
    required this.size,
    required this.radius,
  }) : name = p?.name ?? '',
       color = p?.color ?? '',
       avatar = p?.avatar ?? '',
       photo = p?.photo ?? '',
       localPhoto = null;

  @override
  Widget build(BuildContext context) {
    final c = parseHexColor(color);
    final emoji = Center(
      child: Text(
        avatar.isNotEmpty
            ? avatar
            : (name.isNotEmpty ? name.characters.first.toUpperCase() : '?'),
        style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w800),
      ),
    );
    Widget? image;
    if (localPhoto != null) {
      image = Image.memory(
        localPhoto!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (photo.isNotEmpty) {
      image = NetImage(photo, placeholder: emoji);
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [c, Color.lerp(c, Colors.black, 0.45)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: image ?? emoji,
    );
  }
}
