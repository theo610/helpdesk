import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../models/ticket_model.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({Key? key}) : super(key: key);

  @override
  _StatsScreenState createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _moderatorPlatform;
  double _averageTimeToFirstResponse = 0.0;
  double _averageTimeToResolution = 0.0;
  List<Ticket> _firstResponseOutliers = [];
  List<Ticket> _resolutionOutliers = [];
  bool _isLoading = true;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  Map<String, int> _ticketCounts = {'created': 0, 'in_progress': 0, 'resolved': 0};

  @override
  void initState() {
    super.initState();
    _fetchModeratorPlatformAndStats();
  }

  Future<void> _fetchModeratorPlatformAndStats() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        throw Exception('User data not found');
      }
      final userData = userDoc.data() as Map<String, dynamic>;
      _moderatorPlatform = userData['platform'] as String?;
      if (_moderatorPlatform == null) {
        throw Exception('Moderator platform not specified');
      }

      await _fetchResponseTimeStats();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading statistics: $e', style: GoogleFonts.poppins()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchResponseTimeStats() async {
    if (_moderatorPlatform == null) return;

    final snapshot = await _firestore
        .collection('tickets')
        .where('platform', isEqualTo: _moderatorPlatform)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedDateRange.start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_selectedDateRange.end))
        .get();

    List<Ticket> tickets = snapshot.docs.map((doc) => Ticket.fromFirestore(doc)).toList();

    if (tickets.isEmpty) {
      setState(() {
        _averageTimeToFirstResponse = 0.0;
        _averageTimeToResolution = 0.0;
        _firstResponseOutliers = [];
        _resolutionOutliers = [];
        _ticketCounts = {'created': 0, 'in_progress': 0, 'resolved': 0};
      });
      return;
    }

    double totalFirstResponseTime = 0.0;
    int firstResponseCount = 0;
    double totalResolutionTime = 0.0;
    int resolutionCount = 0;
    _ticketCounts = {'created': 0, 'in_progress': 0, 'resolved': 0};
    _firstResponseOutliers = [];
    _resolutionOutliers = [];

    for (var ticket in tickets) {
      if (ticket.createdAt.isAfter(_selectedDateRange.start) && ticket.createdAt.isBefore(_selectedDateRange.end)) {
        _ticketCounts['created'] = _ticketCounts['created']! + 1;
        if (ticket.status == 'in_progress') _ticketCounts['in_progress'] = _ticketCounts['in_progress']! + 1;
        if (ticket.status == 'resolved') _ticketCounts['resolved'] = _ticketCounts['resolved']! + 1;
      }

      final timeToFirstResponse = ticket.getTimeToFirstResponse();
      if (timeToFirstResponse > 0) {
        totalFirstResponseTime += timeToFirstResponse;
        firstResponseCount++;
        if ((ticket.priority == 'critical' && timeToFirstResponse > 60) ||
            (ticket.priority == 'high' && timeToFirstResponse > 120) ||
            (ticket.priority == 'medium' && timeToFirstResponse > 240) ||
            (ticket.priority == 'low' && timeToFirstResponse > 480)) {
          _firstResponseOutliers.add(ticket);
        }
      }

      final timeToResolution = ticket.getTimeToResolution();
      if (timeToResolution > 0) {
        totalResolutionTime += timeToResolution;
        resolutionCount++;
        if ((ticket.priority == 'critical' && timeToResolution > 120) ||
            (ticket.priority == 'high' && timeToResolution > 240) ||
            (ticket.priority == 'medium' && timeToResolution > 480) ||
            (ticket.priority == 'low' && timeToResolution > 960)) {
          _resolutionOutliers.add(ticket);
        }
      }
    }

    setState(() {
      _averageTimeToFirstResponse = firstResponseCount > 0 ? totalFirstResponseTime / firstResponseCount : 0.0;
      _averageTimeToResolution = resolutionCount > 0 ? totalResolutionTime / resolutionCount : 0.0;
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        final isLightTheme = Theme.of(context).brightness == Brightness.light;
        final surfaceColor = isLightTheme ? Colors.grey[100]! : Colors.grey[900]!;
        final onSurfaceColor = isLightTheme ? Colors.black87 : Colors.white;
        final onSurfaceVariantColor = isLightTheme ? Colors.grey[700]! : Colors.grey[300]!;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: surfaceColor,
              onSurface: onSurfaceColor,
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: onSurfaceVariantColor,
                textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            dialogBackgroundColor: surfaceColor,
            dialogTheme: DialogTheme(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: surfaceColor,
              titleTextStyle: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: onSurfaceColor,
              ),
              contentTextStyle: GoogleFonts.poppins(
                fontSize: 16,
                color: onSurfaceColor,
              ),
            ),
            textTheme: Theme.of(context).textTheme.copyWith(
              bodyMedium: GoogleFonts.poppins(
                fontSize: 16,
                color: onSurfaceColor,
              ),
              labelMedium: GoogleFonts.poppins(
                fontSize: 14,
                color: onSurfaceColor,
              ),
            ),
          ),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
                maxWidth: 400,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Date Range',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: onSurfaceColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      child!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
        _isLoading = true;
      });
      await _fetchResponseTimeStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.background,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.8),
            ],
          ),
        ),
        child: _isLoading
            ? Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        )
            : _buildStatsContent(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading
            ? null
            : () async {
          setState(() => _isLoading = true);
          await _fetchModeratorPlatformAndStats();
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.refresh,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        tooltip: 'Refresh',
      ),
    );
  }

  Widget _buildStatsContent() {
    return AnimationLimiter(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(child: widget),
            ),
            children: [
              _buildDateRangeSelector(),
              const SizedBox(height: 24),
              _buildResponseTimeChart(),
              const SizedBox(height: 24),
              _buildTicketVolumeChart(),
              const SizedBox(height: 24),
              _buildOutliersSection(
                  'First Response Outliers', _firstResponseOutliers, (ticket) => ticket.getTimeToFirstResponse()),
              const SizedBox(height: 24),
              _buildOutliersSection('Resolution Outliers', _resolutionOutliers, (ticket) => ticket.getTimeToResolution()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date Range',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'From ${_selectedDateRange.start.toLocal().toString().split(' ')[0]} to ${_selectedDateRange.end.toLocal().toString().split(' ')[0]}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _selectDateRange,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: Text(
                'Pick Range',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseTimeChart() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Response & Resolution Times',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (_averageTimeToFirstResponse > _averageTimeToResolution
                      ? _averageTimeToFirstResponse
                      : _averageTimeToResolution) * 1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final title = group.x == 0 ? 'First Response' : 'Resolution';
                        return BarTooltipItem(
                          '$title\n${rod.toY.toStringAsFixed(1)} min',
                          GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt() == 0 ? 'First Response' : 'Resolution',
                            style: GoogleFonts.poppins(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()} min',
                            style: GoogleFonts.poppins(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: _averageTimeToFirstResponse,
                          color: Theme.of(context).colorScheme.primary,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: _averageTimeToResolution,
                          color: Colors.green,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketVolumeChart() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket Volume by Status',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      color: Theme.of(context).colorScheme.primary,
                      value: _ticketCounts['created']!.toDouble(),
                      title: 'Created\n${_ticketCounts['created']}',
                      radius: 50,
                      titleStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.yellow,
                      value: _ticketCounts['in_progress']!.toDouble(),
                      title: 'In Progress\n${_ticketCounts['in_progress']}',
                      radius: 50,
                      titleStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.green,
                      value: _ticketCounts['resolved']!.toDouble(),
                      title: 'Resolved\n${_ticketCounts['resolved']}',
                      radius: 50,
                      titleStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                  sectionsSpace: 0,
                  centerSpaceRadius: 40,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        return;
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutliersSection(String title, List<Ticket> outliers, double Function(Ticket) timeExtractor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            outliers.isEmpty
                ? Text(
              'No outliers detected.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: outliers.length,
              itemBuilder: (context, index) {
                final ticket = outliers[index];
                final time = timeExtractor(ticket);
                return ListTile(
                  title: Text(
                    'Ticket ID: ${ticket.id}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Priority: ${ticket.priority}\nTime: ${time.toStringAsFixed(1)} minutes',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.warning,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  onTap: () {
                    // Optionally navigate to ticket details
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
