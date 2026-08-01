//
//  MeetingRowView.swift
//  CharBar
//
//  Smart Meeting UI - Glass morphism design with video link detection
//

import SwiftUI
import EventKit
import Combine

// MARK: - Meeting Menu View (Full Dropdown)
struct MeetingMenuView: View {
    /// true when shown in the floating pop-out window (vs. the inline dropdown)
    var isPopout: Bool = false
    @ObservedObject var meetingManager = MeetingManager.shared
    @State private var showDatePicker = false
    
    /// Contextual status text for the header (always based on today's real events)
    
    private var contextualStatus: String {
        let todaysMeetings = meetingManager.todaysUpcomingMeetings
        if todaysMeetings.isEmpty { return "All clear today" }
        if let happening = todaysMeetings.first(where: { $0.isHappeningNow }) {
            return "In \(happening.title)"
        }
        if let next = todaysMeetings.first(where: { !$0.isHappeningNow }) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Next at \(formatter.string(from: next.startDate))"
        }
        return "\(todaysMeetings.count) today"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            switch meetingManager.accessState {
            case .authorized:
                // Fixed header
                titleHeader

                Divider()
                    .background(Color(NSColor.separatorColor))

                // Single scrollable middle — both NEXT UP and Today live here so
                // there's only one scroll affordance for the user.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        currentTaskSection

                        Divider()
                            .background(Color(NSColor.separatorColor))
                            .padding(.vertical, 4)

                        allTodaysTasksSection
                    }
                }

                // Fixed footer (Open Calendar / Pop Out)
                footerSection

            case .notDetermined:
                requestAccessView
            case .denied, .restricted:
                accessDeniedView
            }
        }
        .frame(width: 360)
        .padding(.horizontal, 10)
        .onAppear {
            meetingManager.goToToday()
            if meetingManager.accessState == .authorized {
                meetingManager.fetchMeetings()
            }
        }
    }
    
    // MARK: - Current Task Section (shows NOW or next 1-2 tasks, scrollable)
    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT UP")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .tracking(1)
            
            if meetingManager.todaysUpcomingMeetings.isEmpty {
                freeTimeView
            } else {
                VStack(spacing: 6) {
                    ForEach(meetingManager.todaysUpcomingMeetings, id: \.id) { meeting in
                        MeetingRowView(
                            meeting: meeting,
                            isHighlighted: meeting.isHappeningNow,
                            showCountdownBadge: meeting.id == meetingManager.displayMeeting?.id
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Free Time View (replaces empty "No meetings" state)
    private var freeTimeView: some View {
        HStack(spacing: 12) {
            // Relaxing icon - monochromatic
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(meetingManager.freeTimeMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Enjoy the quiet time")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }
    
    // MARK: - All Today's Tasks Section
    private var allTodaysTasksSection: some View {
        VStack(spacing: 0) {
            // Date navigation header
            dateNavigationSection

            // All meetings for selected date — flows in the parent ScrollView
            VStack(spacing: 6) {
                if meetingManager.isLoading {
                    loadingView
                } else if meetingManager.upcomingMeetings.isEmpty {
                    emptyDateView
                } else {
                    meetingListWithNowIndicator
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Smart Meeting List with Now Indicator (ONE line only)
    @ViewBuilder
    private var meetingListWithNowIndicator: some View {
        let sortedMeetings = meetingManager.upcomingMeetings.sorted { $0.startDate < $1.startDate }
        let now = Date()
        
        // Find the correct position for the "Now" line
        let nowLineIndex: Int? = {
            guard meetingManager.isViewingToday else { return nil }
            
            for (index, meeting) in sortedMeetings.enumerated() {
                // Show before first meeting that's happening now or in the future
                if meeting.isHappeningNow || meeting.startDate > now {
                    return index
                }
            }
            // All meetings are in the past - show at the end
            return sortedMeetings.count
        }()
        
        ForEach(Array(sortedMeetings.enumerated()), id: \.element.id) { index, meeting in
            // Insert "Now" line at the calculated position
            if let nowIdx = nowLineIndex, index == nowIdx {
                nowIndicatorLine
            }
            
            // Meeting row - fade past meetings; no countdown badge in the full list (only NEXT UP shows it)
            MeetingRowView(
                meeting: meeting,
                isHighlighted: meeting.isHappeningNow,
                showCountdownBadge: false
            )
            .opacity(meeting.endDate < now && !meeting.isHappeningNow ? 0.5 : 1.0)
        }
        
        // If "Now" line should be at the end (all past meetings)
        if let nowIdx = nowLineIndex, nowIdx == sortedMeetings.count {
            nowIndicatorLine
        }
    }
    
    // MARK: - Title Header (Modern Apple-style)
    private var titleHeader: some View {
        HStack(spacing: 10) {
            // Icon - monochromatic
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Text("Meetings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
            
            Spacer()
            
            // Status pill with indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 7, height: 7)
                
                Text(contextualStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(NSColor.labelColor).opacity(0.06))
            )
            
            Button(action: { meetingManager.fetchMeetings() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
    
    private var statusIndicatorColor: Color {
        let meetings = meetingManager.todaysUpcomingMeetings
        if meetings.isEmpty { return .white.opacity(0.5) }
        if meetings.first?.isHappeningNow == true { return .white }
        return .white.opacity(0.7)
    }
    
    // MARK: - Next Task Today Section (FIXED - Always shows today's upcoming tasks)
    private var upcomingTodaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT TASK TODAY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            if meetingManager.todaysUpcomingMeetings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                    Text("All clear for today")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                // Show all imminent meetings (NOW or within 30 mins)
                ForEach(meetingManager.todaysUpcomingMeetings, id: \.id) { meeting in
                    MeetingRowView(
                        meeting: meeting,
                        isHighlighted: meeting.isHappeningNow,
                        showCountdownBadge: meeting.id == meetingManager.displayMeeting?.id
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Date Navigation Section with Week Strip
    private var dateNavigationSection: some View {
        let calendar = Calendar.current
        
        return VStack(spacing: 10) {
            // Header row
            HStack {
                Text(sectionDateTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Spacer()
                
                // Back to Today button
                if !meetingManager.isViewingToday {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            meetingManager.goToToday()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                            Text("Today")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                
                // Event count
                if !meetingManager.upcomingMeetings.isEmpty {
                    Text("\(meetingManager.upcomingMeetings.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary))
                }
            }
            
            // Week navigation with arrows
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: meetingManager.selectedDate) {
                            meetingManager.goToDate(newDate)
                        }
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor.opacity(0.1)))
                }
                .buttonStyle(.plain)
                
                // Week strip
                weekStripView
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: meetingManager.selectedDate) {
                            meetingManager.goToDate(newDate)
                        }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            
            // Expandable full calendar
            if showDatePicker {
                fullCalendarView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Week Strip View
    private var weekStripView: some View {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: meetingManager.selectedDate))!
        let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
        
        return HStack(spacing: 4) {
            ForEach(weekDates, id: \.self) { date in
                MenuWeekDayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: meetingManager.selectedDate),
                    isToday: calendar.isDateInToday(date)
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        meetingManager.goToDate(date)
                    }
                }
            }
        }
    }
    
    // MARK: - Full Calendar View (Expandable)
    private var fullCalendarView: some View {
        VStack(spacing: 8) {
            // Month header
            HStack {
                Button(action: {
                    if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: meetingManager.selectedDate) {
                        meetingManager.goToDate(newDate)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(monthYearString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Spacer()
                
                Button(action: {
                    if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: meetingManager.selectedDate) {
                        meetingManager.goToDate(newDate)
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            // Days header
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days grid
            let days = generateDaysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        MenuCalendarDayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: meetingManager.selectedDate),
                            isToday: Calendar.current.isDateInToday(date)
                        ) {
                            withAnimation {
                                meetingManager.goToDate(date)
                                showDatePicker = false
                            }
                        }
                    } else {
                        Text("").frame(width: 30, height: 30)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.labelColor).opacity(0.04))
        )
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: meetingManager.selectedDate)
    }
    
    private func generateDaysInMonth() -> [Date?] {
        let calendar = Calendar.current
        var days: [Date?] = []
        let range = calendar.range(of: .day, in: .month, for: meetingManager.selectedDate)!
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: meetingManager.selectedDate))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
        
        for _ in 0..<firstWeekday { days.append(nil) }
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        return days
    }
    
    private var sectionDateTitle: String {
        if meetingManager.isViewingToday {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(meetingManager.selectedDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: meetingManager.selectedDate)
        }
    }
    
    // MARK: - Empty Date View (Smart Free Time)
    private var emptyDateView: some View {
        VStack(spacing: 12) {
            // Icon - monochromatic
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 50, height: 50)
                
                Image(systemName: meetingManager.isViewingToday ? "checkmark" : "calendar")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white.opacity(meetingManager.isViewingToday ? 0.7 : 0.4))
            }
            
            VStack(spacing: 4) {
                Text(meetingManager.isViewingToday ? "All Clear" : "Nothing scheduled")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(meetingManager.isViewingToday ? meetingManager.freeTimeMessage : "This day is free")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Now Indicator Line
    private var nowIndicatorLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 8, height: 8)
            
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 1)
            
            Text(formattedCurrentTime)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private var formattedCurrentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
    
    // MARK: - Header (OLD - kept for reference but not used)
    private var headerSection: some View {
        VStack(spacing: 8) {
            // Title row
        HStack {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.4, green: 0.75, blue: 0.65)) // Soft teal
            
            Text("Smart Meetings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Refresh button
            Button(action: {
                meetingManager.fetchMeetings()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
            
            // Date Navigation Row
            HStack(spacing: 16) {
                // Previous day button
                Button(action: {
                    meetingManager.goToPreviousDay()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Current date display
                VStack(spacing: 2) {
                    Text(meetingManager.selectedDateText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(meetingManager.formattedFullDate)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Next day button
                Button(action: {
                    meetingManager.goToNextDay()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            
            // "Back to Today" button (if not viewing today)
            if !meetingManager.isViewingToday {
                Button(action: {
                    meetingManager.goToToday()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Back to Today")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.4, green: 0.75, blue: 0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.4, green: 0.75, blue: 0.65).opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Loading events...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .glassCard(cornerRadius: 12, opacity: 0.06)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
    }
    
    // MARK: - No Events View
    private var noMeetingsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.4))
            
            VStack(spacing: 6) {
                Text("Nothing scheduled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("Enjoy your free time!")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Tip to add Google Calendar
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow.opacity(0.7))
                Text("To add Google Calendar, check Meetings settings")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .glassCard(cornerRadius: 12, opacity: 0.06)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
    }
    
    // MARK: - Request Access View
    private var requestAccessView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Calendar icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Text
            VStack(spacing: 8) {
                Text("Calendar Access")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Allow CharBar to read your calendar\nto show upcoming meetings and events")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            // Grant Access Button
            Button(action: {
                meetingManager.requestAccess()
            }) {
                Text("Allow Calendar Access")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Access Denied View
    private var accessDeniedView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Lock icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "lock.shield")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Text
            VStack(spacing: 8) {
                Text("Calendar Access Denied")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Calendar access was denied.\nEnable it in System Settings to see your events.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            // Open Settings Button
            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                    Text("Open System Settings")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: 220)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.85))
                )
            }
            .buttonStyle(.plain)
            
            // Recheck access link
            Button(action: {
                meetingManager.checkAccessStatus()
                if meetingManager.accessState == .authorized {
                    meetingManager.fetchMeetings()
                }
            }) {
                Text("I've granted access →")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Meeting Content
    private func meetingContent(_ meeting: SmartMeeting) -> some View {
        VStack(spacing: 0) {
            MeetingRowView(meeting: meeting, isHighlighted: true)
        }
        .glassCard(cornerRadius: 14, opacity: 0.06)
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Upcoming Section
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UPCOMING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.top, 12)
            
            VStack(spacing: 6) {
                ForEach(meetingManager.upcomingMeetings.dropFirst().prefix(5)) { meeting in
                    MeetingRowView(meeting: meeting, isHighlighted: false, showCountdownBadge: false)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, opacity: 0.06)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
    
    // MARK: - Footer
    private var footerSection: some View {
        CalendarFooterView(showPopOut: !isPopout)
    }
}

// MARK: - Menu Week Day Cell (Compact)
struct MenuWeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(dayLetter)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : (isToday ? .accentColor : Color(NSColor.labelColor)))
            }
            .frame(width: 34, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dayLetter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Menu Calendar Day Cell (Full Grid)
struct MenuCalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
                
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? .accentColor : Color(NSColor.labelColor)))
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Footer View (with pop-out and open in Calendar)
struct CalendarFooterView: View {
    /// Pass false when already inside the pop-out window to hide the "Pop Out" button
    var showPopOut: Bool = true
    @ObservedObject var meetingManager = MeetingManager.shared
    @State private var isHoveringOpen = false
    @State private var isHoveringPopout = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Open in Calendar button
            Button(action: {
                meetingManager.openCalendarToSelectedDate()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                    Text("Open Calendar")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(isHoveringOpen ? 0.9 : 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isHoveringOpen ? 0.1 : 0.06))
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHoveringOpen = hovering }
            }
            
            if showPopOut {
                Button(action: {
                    FloatingCalendarController.shared.show()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 12, weight: .medium))
                        Text("Pop Out")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(isHoveringPopout ? 0.9 : 0.8))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { isHoveringPopout = hovering }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Meeting Row View (Modern Apple-style)
struct MeetingRowView: View {
    let meeting: SmartMeeting
    let isHighlighted: Bool
    var showCountdownBadge: Bool = true
    
    @State private var isHovering = false
    @State private var showOptionsMenu = false
    @State private var now = Date()
    @Environment(\.colorScheme) var colorScheme
    
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var isPast: Bool {
        meeting.endDate < Date() && !meeting.isHappeningNow
    }
    
    private var countdownText: String? {
        guard showCountdownBadge else { return nil }
        guard !isPast else { return nil }
        if meeting.isHappeningNow { return nil }
        let t = meeting.startDate.timeIntervalSince(now)
        guard t > 0 else { return nil }
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remainMins = mins % 60
            return "In \(hrs)h \(remainMins)m"
        }
        return "In \(mins):\(String(format: "%02d", secs))"
    }
    
    private var countdownBadgeColor: Color {
        let t = meeting.startDate.timeIntervalSince(now)
        if t <= 60 { return .red }
        if t <= 300 { return .orange }
        return .orange.opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Title + Countdown badge
            HStack(alignment: .center) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(NSColor.labelColor))
                    .opacity(isPast ? 0.5 : 1)
                    .lineLimit(1)
                
                Spacer()
                
                if let countdown = countdownText {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(countdownBadgeColor)
                            .frame(width: 6, height: 6)
                        Text(countdown)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(countdownBadgeColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(countdownBadgeColor.opacity(0.12))
                    )
                } else if meeting.isHappeningNow {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Now")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                    )
                }
            }
            
            // Row 2: Time range + video platform
            HStack(spacing: 8) {
                Label(meeting.formattedTimeRange, systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                
                if meeting.hasVideoLink {
                    Label(meeting.meetingLinkType?.brandName ?? "Video", systemImage: "video.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(meeting.meetingLinkType?.color ?? .blue)
                }
            }
            
            // Row 3: Action buttons (Join + Late + ...)
            if !isPast {
                HStack(spacing: 8) {
                    if meeting.hasVideoLink {
                        Button(action: { MeetingManager.shared.joinMeeting(meeting) }) {
                            Text("Join Meeting")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(meeting.isHappeningNow ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(meeting.isHappeningNow ? Color.green : Color.white.opacity(0.85))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        // Quick late button
                        Button(action: {
                            if let event = meeting.event {
                                EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 5)
                            }
                        }) {
                            Text("Late 5m")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(NSColor.labelColor).opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No video — just time remaining and options
                        HStack {
                            Text(meeting.timeRemainingString)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            RunningLateMenuButton(meeting: meeting)
                        }
                    }
                    
                    if meeting.hasVideoLink {
                        RunningLateMenuButton(meeting: meeting)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.labelColor).opacity(isHovering ? 0.08 : 0.04))
        )
        .opacity(isPast ? 0.6 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onReceive(countdownTimer) { _ in
            now = Date()
        }
    }
    
    private func sendRunningLate(_ minutes: Int) {
        if let event = meeting.event {
            EmailHelper.shared.sendRunningLateEmail(for: event, minutes: minutes)
        }
    }
    
    private func openInCalendar() {
        if let event = meeting.event {
            MeetingManager.shared.openEventInCalendar(event: event)
        }
    }
    
    private var normalMeetingRow: some View {
        body
    }
    
    private var videoMeetingRow: some View {
        Button(action: {
            MeetingManager.shared.joinMeeting(meeting)
        }) {
            HStack(spacing: 14) {
                // Calendar color pill
                RoundedRectangle(cornerRadius: 4)
                    .fill(meeting.calendarColor)
                    .frame(width: 5, height: isHighlighted ? 60 : 48)
                
                // Event details
                VStack(alignment: .leading, spacing: 5) {
                    Text(meeting.title)
                        .font(.system(size: isHighlighted ? 14 : 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 5) {
                        // Meeting type icon
                        Image(systemName: meeting.meetingLinkType?.icon ?? "video.fill")
                            .font(.system(size: 11))
                            .foregroundColor(meeting.meetingLinkType?.color ?? .blue)
                        
                        Text(meeting.meetingLinkType?.brandName ?? "Video Call")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(meeting.meetingLinkType?.color ?? .blue)
                        
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text(meeting.formattedTimeRange)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                // Join Button
                joinButton
                
                // Options Menu (Running Late, etc.)
                meetingOptionsMenu
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isHighlighted ? 16 : 12)
            .background(
                ZStack {
                    // Base glass effect
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    
                    // Color gradient overlay
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                    (meeting.meetingLinkType?.color ?? .blue).opacity(isHovering ? 0.25 : 0.12),
                                    (meeting.meetingLinkType?.color ?? .blue).opacity(isHovering ? 0.15 : 0.06)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        )
                }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                    .stroke((meeting.meetingLinkType?.color ?? .blue).opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    // MARK: - Meeting Options Menu (Running Late, etc.)
    private var meetingOptionsMenu: some View {
        Menu {
            // Running Late Section
            Section("Running Late?") {
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 5)
                    }
                }) {
                    Label("5 mins late", systemImage: "clock.badge.exclamationmark")
                }
                
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 10)
                    }
                }) {
                    Label("10 mins late", systemImage: "clock.badge.exclamationmark")
                }
                
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 15)
                    }
                }) {
                    Label("15 mins late", systemImage: "clock.badge.exclamationmark")
                }
            }
            
            Divider()
            
            // Calendar Actions
            Button(action: {
                if let event = meeting.event {
                    EmailHelper.shared.showInCalendar(event: event)
                }
            }) {
                Label("Show in Calendar", systemImage: "calendar")
            }
            
            // Copy Link
            if meeting.hasVideoLink, let link = meeting.videoLink {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                }) {
                    Label("Copy Meeting Link", systemImage: "link")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
    
    // MARK: - Join Button with Countdown Timer
    private var joinButton: some View {
        JoinButtonWithTimer(meeting: meeting, isHovering: isHovering)
    }
    
    // MARK: - Time Remaining Badge
    private var timeRemainingBadge: some View {
        Group {
            if meeting.isHappeningNow {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                    
                    Text("Now")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
            } else if meeting.isStartingSoon {
                Text(meeting.timeRemainingString)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            } else {
                Text(meeting.timeRemainingString)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Join Button with Live Countdown and Menu
struct JoinButtonWithTimer: View {
    let meeting: SmartMeeting
    let isHovering: Bool
    
    @State private var countdown: Int = 0
    @State private var timer: Timer?
    
    private var buttonText: String {
        if meeting.isHappeningNow {
            return "Join Now"
        } else if countdown > 0 && countdown <= 120 {
            // Show countdown when 2 mins or less
            return "Join \(formatCountdown(countdown))"
        } else if meeting.isStartingSoon {
            return "Join Now"
        } else {
            return "Join"
        }
    }
    
    private var buttonColor: Color {
        countdown > 0 && countdown <= 60 
            ? Color.white 
            : Color.white.opacity(0.85)
    }
    
    var body: some View {
        // Menu with primary action: click joins, menu shows more options
        Menu {
            // Primary: Join the meeting
            Button(action: {
                MeetingManager.shared.joinMeeting(meeting)
            }) {
                Label("Join Meeting", systemImage: "video.fill")
            }
            
            Divider()
            
            // Running Late options
            Section("Running Late?") {
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 5)
                    }
                }) {
                    Label("5 mins late", systemImage: "clock.badge.exclamationmark")
                }
                
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 10)
                    }
                }) {
                    Label("10 mins late", systemImage: "clock.badge.exclamationmark")
                }
                
                Button(action: {
                    if let event = meeting.event {
                        EmailHelper.shared.sendRunningLateEmail(for: event, minutes: 15)
                    }
                }) {
                    Label("15 mins late", systemImage: "clock.badge.exclamationmark")
                }
            }
            
            Divider()
            
            // Copy link
            if meeting.hasVideoLink, let link = meeting.videoLink {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                }) {
                    Label("Copy Meeting Link", systemImage: "link")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(buttonText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                
                // Small chevron to indicate menu
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(buttonColor)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: countdown <= 60)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startCountdown() {
        countdown = Int(max(0, meeting.timeUntilStart))
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let newCountdown = Int(max(0, meeting.timeUntilStart))
            if newCountdown != countdown {
                countdown = newCountdown
            }
        }
    }
    
    private func formatCountdown(_ seconds: Int) -> String {
        if seconds < 60 {
            return "in \(seconds)s"
        } else {
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d", mins, secs)
        }
    }
}

// MARK: - Compact Menu Bar View
struct MeetingCompactView: View {
    @ObservedObject var meetingManager = MeetingManager.shared
    
    var body: some View {
        if let meeting = meetingManager.currentMeeting {
            HStack(spacing: 6) {
                // Small calendar dot - monochromatic
                Circle()
                    .fill(Color.white.opacity(meeting.isHappeningNow ? 0.9 : 0.5))
                    .frame(width: 6, height: 6)
                
                if meeting.hasVideoLink && (meeting.isHappeningNow || meeting.isStartingSoon) {
                    // Show video icon for imminent video meetings
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Text(meeting.timeRemainingString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(meeting.isHappeningNow ? .white : .white.opacity(0.7))
            }
        }
    }
}

// MARK: - Running Late Menu Button (Apple-style)

struct RunningLateMenuButton: View {
    let meeting: SmartMeeting
    @State private var isHovering = false
    @State private var isPressed = false
    
    var body: some View {
        Menu {
            Section {
                Button(action: { sendRunningLate(5) }) {
                    Label("5 minutes late", systemImage: "clock.badge.exclamationmark")
                }
                Button(action: { sendRunningLate(10) }) {
                    Label("10 minutes late", systemImage: "clock.badge.exclamationmark")
                }
                Button(action: { sendRunningLate(15) }) {
                    Label("15 minutes late", systemImage: "clock.badge.exclamationmark")
                }
                Button(action: { sendRunningLate(20) }) {
                    Label("20 minutes late", systemImage: "clock.badge.exclamationmark")
                }
            } header: {
                Text("Send Running Late Email")
            }
            
            Divider()
            
            Section {
                Button(action: { skipMeeting() }) {
                    Label("Skip This Meeting", systemImage: "xmark.circle")
                }
                
                if meeting.hasVideoLink {
                    Button(action: { shareMeeting() }) {
                        Label("Share Meeting Link", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { copyMeetingLink() }) {
                        Label("Copy Meeting Link", systemImage: "doc.on.doc")
                    }
                }
            }
            
            Divider()
            
            Button(action: { openInCalendar() }) {
                Label("Show in Calendar", systemImage: "calendar")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isHovering ? 0.15 : 0.06))
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isHovering ? .primary : .secondary)
                    .rotationEffect(.degrees(isPressed ? 15 : 0))
            }
            .frame(width: 24, height: 24)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovering)
            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
    
    private func sendRunningLate(_ minutes: Int) {
        if let event = meeting.event {
            EmailHelper.shared.sendRunningLateEmail(for: event, minutes: minutes)
        }
    }
    
    private func skipMeeting() {
        if let event = meeting.event {
            let subject = "Unable to Attend: \(event.title ?? "Meeting")"
            let body = "Hi,\n\nI won't be able to make it to \(event.title ?? "the meeting") today. Apologies for the inconvenience.\n\nBest regards"
            let emails = (event.attendees ?? []).compactMap { attendee -> String? in
                if attendee.isCurrentUser { return nil }
                let url = attendee.url.absoluteString
                return url.hasPrefix("mailto:") ? String(url.dropFirst(7)) : nil
            }
            EmailHelper.shared.openMailto(to: emails, subject: subject, body: body)
        }
    }
    
    private func shareMeeting() {
        var shareText = "\(meeting.title)\n\(meeting.formattedTimeRange)"
        if let link = meeting.meetingLink {
            shareText += "\n\nJoin: \(link.absoluteString)"
        }
        let picker = NSSharingServicePicker(items: [shareText])
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
           let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
    
    private func copyMeetingLink() {
        if let link = meeting.meetingLink {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.absoluteString, forType: .string)
        }
    }
    
    private func openInCalendar() {
        if let event = meeting.event {
            MeetingManager.shared.openEventInCalendar(event: event)
        }
    }
}

#Preview {
    MeetingMenuView()
        .frame(width: 340, height: 500)
        .background(Color.black.opacity(0.5))
}

