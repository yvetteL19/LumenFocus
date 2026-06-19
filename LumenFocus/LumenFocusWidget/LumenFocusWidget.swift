//
//  LumenFocusWidget.swift
//  LumenFocusWidget
//
//  Two sizes:
//   - small: today's rest count + ring progress
//   - medium: 7-day bar chart + streak
//

import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let restCount: Int
    let workSeconds: Int
    let streak: Int
    let weeklyBars: [Int]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), restCount: 4, workSeconds: 2 * 3600, streak: 3, weeklyBars: [2, 3, 5, 4, 3, 6, 4])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // 每 30 分钟刷新一次。主 app 写入后 WidgetCenter.reloadAllTimelines() 会立刻生效
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [currentEntry()], policy: .after(next))
        completion(timeline)
    }

    private func currentEntry() -> TodayEntry {
        let snapshot = SharedDataAccess.readTodaySnapshot()
        return TodayEntry(
            date: Date(),
            restCount: snapshot.restCount,
            workSeconds: snapshot.workSeconds,
            streak: snapshot.currentStreak,
            weeklyBars: snapshot.weeklyBars
        )
    }
}

// MARK: - Small widget

struct SmallTodayView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye.fill")
                Spacer()
                if entry.streak > 0 {
                    Text("🔥 \(entry.streak)")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundColor(.primary)

            Spacer()
            Text("\(entry.restCount)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("今日护眼")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .containerBackground(for: .widget) { Color(.windowBackgroundColor) }
    }
}

// MARK: - Medium widget

struct MediumTodayView: View {
    let entry: TodayEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(entry.restCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("今日护眼")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if entry.streak > 0 {
                    Text("连续 \(entry.streak) 天")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("近 7 日")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Chart(Array(entry.weeklyBars.enumerated()), id: \.offset) { idx, value in
                    BarMark(
                        x: .value("日", idx),
                        y: .value("次", value)
                    )
                    .foregroundStyle(.primary)
                    .cornerRadius(2)
                }
                .frame(height: 70)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { Color(.windowBackgroundColor) }
    }
}

// MARK: - Widget config

struct LumenFocusSmallWidget: Widget {
    let kind: String = "Yvette.LumenFocus.TodaySmall"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            SmallTodayView(entry: entry)
        }
        .configurationDisplayName("今日护眼")
        .description("一眼看到今日的护眼次数与 streak")
        .supportedFamilies([.systemSmall])
    }
}

struct LumenFocusMediumWidget: Widget {
    let kind: String = "Yvette.LumenFocus.TodayMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            MediumTodayView(entry: entry)
        }
        .configurationDisplayName("近 7 日护眼")
        .description("今日次数 + streak + 7 日 bar")
        .supportedFamilies([.systemMedium])
    }
}
