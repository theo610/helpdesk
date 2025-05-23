import 'package:cloud_firestore/cloud_firestore.dart';

class Ticket {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String? platform;
  final String? platformName;
  final String? equipment;
  final String? equipmentName;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? firstResponseAt;
  final DateTime? resolvedAt;
  final String? assignedTo;
  final bool reassigned;
  final List<String>? imageUrls;

  Ticket({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.platform,
    this.platformName,
    this.equipment,
    this.equipmentName,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.firstResponseAt,
    this.resolvedAt,
    this.assignedTo,
    this.reassigned = false,
    this.imageUrls,
  });

  factory Ticket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Ticket(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'open',
      priority: data['priority'] ?? 'low',
      platform: data['platform'],
      platformName: data['platformName'],
      equipment: data['equipment'],
      equipmentName: data['equipmentName'],
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      firstResponseAt: (data['firstResponseAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      assignedTo: data['assignedTo'],
      reassigned: data['reassigned'] ?? false,
      imageUrls: data['imageUrls'] != null ? List<String>.from(data['imageUrls']) : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    final data = {
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'platform': platform,
      'platformName': platformName ?? platform,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'firstResponseAt': firstResponseAt != null ? Timestamp.fromDate(firstResponseAt!) : null,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'assignedTo': assignedTo,
      'reassigned': reassigned,
      'imageUrls': imageUrls,
    };
    if (equipment != null) {
      data['equipment'] = equipment;
      data['equipmentName'] = equipmentName ?? equipment;
    }
    return data;
  }

  double getTimeToFirstResponse() {
    if (createdAt == null || firstResponseAt == null) return 0.0;
    return firstResponseAt!.difference(createdAt).inMinutes.toDouble();
  }

  double getTimeToResolution() {
    if (firstResponseAt == null || resolvedAt == null) return 0.0;
    return resolvedAt!.difference(firstResponseAt!).inMinutes.toDouble();
  }
}