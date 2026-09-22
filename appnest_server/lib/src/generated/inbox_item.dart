/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _is;

abstract class InboxItem
    implements _is.SerializableModel, _is.ProtocolSerialization {
  InboxItem._({
    required this.id,
    required this.appId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  factory InboxItem({
    required int id,
    required int appId,
    required String title,
    required String body,
    required DateTime createdAt,
    required bool isRead,
  }) = _InboxItemImpl;

  factory InboxItem.fromJson(Map<String, dynamic> jsonSerialization) {
    return InboxItem(
      id: jsonSerialization['id'] as int,
      appId: jsonSerialization['appId'] as int,
      title: jsonSerialization['title'] as String,
      body: jsonSerialization['body'] as String,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      isRead: _is.BoolJsonExtension.fromJson(jsonSerialization['isRead']),
    );
  }

  int id;

  int appId;

  String title;

  String body;

  DateTime createdAt;

  bool isRead;

  /// Returns a shallow copy of this [InboxItem]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  InboxItem copyWith({
    int? id,
    int? appId,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'InboxItem',
      'id': id,
      'appId': appId,
      'title': title,
      'body': body,
      'createdAt': createdAt.toJson(),
      'isRead': isRead,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'InboxItem',
      'id': id,
      'appId': appId,
      'title': title,
      'body': body,
      'createdAt': createdAt.toJson(),
      'isRead': isRead,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _InboxItemImpl extends InboxItem {
  _InboxItemImpl({
    required int id,
    required int appId,
    required String title,
    required String body,
    required DateTime createdAt,
    required bool isRead,
  }) : super._(
         id: id,
         appId: appId,
         title: title,
         body: body,
         createdAt: createdAt,
         isRead: isRead,
       );

  /// Returns a shallow copy of this [InboxItem]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  InboxItem copyWith({
    int? id,
    int? appId,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return InboxItem(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
