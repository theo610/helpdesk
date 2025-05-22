import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({Key? key}) : super(key: key);

  @override
  _AdminStatsScreenState createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  int _totalActiveUsers = 0;
  List<Map<String, dynamic>> _recentlyActiveUsers = [];
  List<Map<String, dynamic>> _activeUsers = [];
  bool _isLoading = true;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  Map<String, int> _roleDistribution = {};
  Map<DateTime, int> _dailyActiveUsers = {};

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all active users within date range, excluding Admins
      Query query = FirebaseFirestore.instance
          .collection('users')
          .where('isActive', isEqualTo: true)
          .where('lastActive', isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedDateRange.start))
          .where('lastActive', isLessThanOrEqualTo: Timestamp.fromDate(_selectedDateRange.end))
          .where('role', isNotEqualTo: 'Admin');

      final activeUsersSnapshot = await query.get();
      final totalActiveUsers = activeUsersSnapshot.docs.length;
      final activeUsers = activeUsersSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'fullName': data['fullName'] ?? 'Unknown',
          'lastActive': (data['lastActive'] as Timestamp?)?.toDate(),
          'role': data['role'] ?? 'N/A',
        };
      }).toList();

      // Fetch recently active users (last 5, sorted by lastActive, excluding Admins)
      final recentUsersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isNotEqualTo: 'Admin')
          .orderBy('lastActive', descending: true)
          .limit(5)
          .get();
      final recentlyActiveUsers = recentUsersSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'fullName': data['fullName'] ?? 'Unknown',
          'lastActive': (data['lastActive'] as Timestamp?)?.toDate(),
          'role': data['role'] ?? 'N/A',
        };
      }).toList();

      // Calculate daily active users for chart
      final dailyActiveUsers = <DateTime, int>{};
      for (var user in activeUsers) {
        final lastActive = user['lastActive'] as DateTime?;
        if (lastActive != null) {
          final date = DateTime(lastActive.year, lastActive.month, lastActive.day);
          dailyActiveUsers[date] = (dailyActiveUsers[date] ?? 0) + 1;
        }
      }

      // Calculate role distribution
      final roleDistribution = <String, int>{};
      for (var user in activeUsers) {
        final role = user['role'] as String;
        roleDistribution[role] = (roleDistribution[role] ?? 0) + 1;
      }

      setState(() {
        _totalActiveUsers = totalActiveUsers;
        _recentlyActiveUsers = recentlyActiveUsers;
        _activeUsers = activeUsers;
        _dailyActiveUsers = dailyActiveUsers;
        _roleDistribution = roleDistribution;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error fetching stats: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      setState(() => _isLoading = false);
    }
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
      await _fetchStats();
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
          await _fetchStats();
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
              _buildTotalActiveUsersCard(),
              const SizedBox(height: 24),
              _buildRoleDistributionChart(),
              const SizedBox(height: 24),
              _buildActivityChart(),
              const SizedBox(height: 24),
              _buildRecentlyActiveUsers(),
              const SizedBox(height: 24),
              _buildAllActiveUsers(),
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

  Widget _buildTotalActiveUsersCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Active Users',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              '$_totalActiveUsers',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleDistributionChart() {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Colors.yellow,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];
    final sections = _roleDistribution.entries.map((entry) {
      final index = _roleDistribution.keys.toList().indexOf(entry.key);
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: entry.value.toDouble(),
        title: '${entry.key}\n${entry.value}',
        radius: 50,
        titleStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      );
    }).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Distribution by Role',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            _roleDistribution.isEmpty
                ? Text(
              'No users available.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
                : SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
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

  Widget _buildActivityChart() {
    final days = _selectedDateRange.end.difference(_selectedDateRange.start).inDays + 1;
    final barGroups = List.generate(days, (index) {
      final date = _selectedDateRange.start.add(Duration(days: index));
      final count = _dailyActiveUsers[DateTime(date.year, date.month, date.day)]?.toDouble() ?? 0.0;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: count,
            color: Theme.of(context).colorScheme.primary,
            width: 15,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Active Users (Non-Admins)',
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
                  maxY: (_dailyActiveUsers.values.isNotEmpty ? _dailyActiveUsers.values.reduce((a, b) => a > b ? a : b) : 1) * 1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final date = _selectedDateRange.start.add(Duration(days: group.x));
                        return BarTooltipItem(
                          '${DateFormat('MMM d').format(date)}\n${rod.toY.toInt()} users',
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
                        reservedSize: 60, // Increased to accommodate rotated labels
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          // Show labels every 2 days if range > 10 days, every day otherwise
                          final skip = days > 10 ? 2 : 1;
                          if (index % skip != 0) return const SizedBox.shrink();
                          final date = _selectedDateRange.start.add(Duration(days: index));
                          return Transform.rotate(
                            angle: -45 * 3.14159 / 180, // Rotate 45 degrees
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                DateFormat('MMM d').format(date),
                                style: GoogleFonts.poppins(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 10, // Smaller font size
                                ),
                              ),
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
                            '${value.toInt()}',
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
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentlyActiveUsers() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recently Active Users',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _recentlyActiveUsers.isEmpty
                ? Text(
              'No recent activity available.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentlyActiveUsers.length,
              itemBuilder: (context, index) {
                final user = _recentlyActiveUsers[index];
                final lastActive = user['lastActive'] as DateTime?;
                final formattedTime = lastActive != null
                    ? DateFormat('MMM d, yyyy, h:mm a').format(lastActive)
                    : 'N/A';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      user['fullName'][0].toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    user['fullName'],
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Role: ${user['role']}\nLast Active: $formattedTime',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllActiveUsers() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All Active Users',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _activeUsers.isEmpty
                ? Text(
              'No active users available.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeUsers.length,
              itemBuilder: (context, index) {
                final user = _activeUsers[index];
                final lastActive = user['lastActive'] as DateTime?;
                final formattedTime = lastActive != null
                    ? DateFormat('MMM d, yyyy, h:mm a').format(lastActive)
                    : 'N/A';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      user['fullName'][0].toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    user['fullName'],
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Role: ${user['role']}\nLast Active: $formattedTime',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}