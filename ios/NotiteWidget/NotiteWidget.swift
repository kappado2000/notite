import SwiftUI
import WidgetKit

// Widgeturile Notițe de pe ecranul principal / ecranul blocat.
// - „Listă Notițe”: lista de bifat aleasă în aplicație („Arată pe widget”)
//   sau cea mai recentă listă cu lucruri nebifate.
// - „Notițe rapide”: notiță nouă, listă, scanare, bon.
// Datele vin din aplicație (fișierul widget.json din grupul comun); widgetul
// nu vede nimic altceva (nici parole, nici notițe blocate).

private let group = "group.com.kappado.notite"
private let accent = Color(red: 0.34, green: 0.47, blue: 0.39)

private func link(_ path: String) -> URL {
  URL(string: "notite://widget/\(path)")!
}

// MARK: - Date

struct WidgetList: Decodable {
  struct Item: Decodable, Hashable {
    let t: String
    let d: Bool
  }

  let id: String
  let title: String
  let open: Int
  let total: Int
  let items: [Item]
}

private struct Payload: Decodable {
  let list: WidgetList?
}

struct ListEntry: TimelineEntry {
  let date: Date
  let list: WidgetList?
}

private let sample = WidgetList(
  id: "", title: "Cumpărături", open: 3, total: 4,
  items: [
    .init(t: "Lapte", d: false), .init(t: "Pâine", d: false),
    .init(t: "Ouă", d: false), .init(t: "Cafea", d: true),
  ])

struct ListProvider: TimelineProvider {
  func placeholder(in context: Context) -> ListEntry {
    ListEntry(date: Date(), list: sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (ListEntry) -> Void) {
    completion(context.isPreview ? ListEntry(date: Date(), list: sample) : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ListEntry>) -> Void) {
    // aplicația cere reîncărcarea la fiecare schimbare a listei
    completion(Timeline(entries: [load()], policy: .never))
  }

  private func load() -> ListEntry {
    guard
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json"),
      let data = try? Data(contentsOf: url),
      let payload = try? JSONDecoder().decode(Payload.self, from: data)
    else { return ListEntry(date: Date(), list: nil) }
    return ListEntry(date: Date(), list: payload.list)
  }
}

struct QuickEntry: TimelineEntry {
  let date: Date
}

struct QuickProvider: TimelineProvider {
  func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
    completion(QuickEntry(date: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
    completion(Timeline(entries: [QuickEntry(date: Date())], policy: .never))
  }
}

// MARK: - Fundal (iOS 17 cere containerBackground)

extension View {
  @ViewBuilder func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { Color(.systemBackground) }
    } else {
      padding().background(Color(.systemBackground))
    }
  }
}

// MARK: - „Listă Notițe”

struct ListWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: ListEntry

  private var limit: Int {
    switch family {
    case .systemLarge: return 12
    case .systemMedium: return 4
    case .accessoryRectangular: return 2
    default: return 4
    }
  }

  var body: some View {
    Group {
      if let list = entry.list {
        content(list)
          .widgetURL(link(list.id.isEmpty ? "new/list" : "note/\(list.id)"))
      } else {
        empty.widgetURL(link("new/list"))
      }
    }
    .widgetBackground()
  }

  @ViewBuilder private func content(_ list: WidgetList) -> some View {
    if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 1) {
        Text(list.title).font(.headline).lineLimit(1)
        ForEach(list.items.prefix(limit), id: \.self) { i in
          Text((i.d ? "✓ " : "○ ") + i.t).font(.caption).lineLimit(1)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(list.title).font(.headline).lineLimit(1)
          Spacer(minLength: 4)
          Text(list.open == 0 ? "gata" : "\(list.open) de făcut")
            .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(list.items.prefix(limit), id: \.self) { i in
          HStack(spacing: 6) {
            Image(systemName: i.d ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(i.d ? accent : Color.secondary)
              .font(.subheadline)
            Text(i.t)
              .font(.subheadline)
              .strikethrough(i.d)
              .foregroundStyle(i.d ? .secondary : .primary)
              .lineLimit(1)
          }
        }
        if list.total > min(limit, list.items.count) {
          Text("+ încă \(list.total - min(limit, list.items.count))")
            .font(.caption2).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var empty: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "checklist").font(.title2).foregroundStyle(accent)
      Text("Nicio listă").font(.headline)
      Text("Atinge ca să faci o listă de bifat.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ListWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NotiteList", provider: ListProvider()) { entry in
      ListWidgetView(entry: entry)
    }
    .configurationDisplayName("Listă Notițe")
    .description("O listă de bifat din Notițe (alege-o din notiță: ⋮ → Arată pe widget).")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
  }
}

// MARK: - „Notițe rapide”

private struct Action: Identifiable {
  let id: String
  let title: String
  let icon: String
}

private let actions = [
  Action(id: "new/note", title: "Notiță", icon: "square.and.pencil"),
  Action(id: "new/list", title: "Listă", icon: "checklist"),
  Action(id: "new/scan", title: "Scanează", icon: "doc.viewfinder"),
  Action(id: "new/bon", title: "Bon", icon: "receipt"),
]

struct QuickWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: QuickEntry

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          Image(systemName: "square.and.pencil").font(.title2)
        }
        .widgetURL(link("new/note"))
      case .accessoryRectangular:
        Label("Notiță nouă", systemImage: "square.and.pencil")
          .font(.headline)
          .widgetURL(link("new/note"))
      case .systemSmall:
        // un widget mic are o singură zonă de atingere: notiță nouă
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(accent)
          Spacer(minLength: 0)
          Text("Notiță nouă").font(.headline)
          Text("Notițe").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(link("new/note"))
      default:
        HStack(spacing: 10) {
          ForEach(actions) { a in
            Link(destination: link(a.id)) {
              VStack(spacing: 6) {
                Image(systemName: a.icon)
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundStyle(accent)
                  .frame(width: 52, height: 52)
                  .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                Text(a.title).font(.caption).foregroundStyle(.primary)
              }
              .frame(maxWidth: .infinity)
            }
          }
        }
      }
    }
    .widgetBackground()
  }
}

struct QuickWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NotiteQuick", provider: QuickProvider()) { entry in
      QuickWidgetView(entry: entry)
    }
    .configurationDisplayName("Notițe rapide")
    .description("Notiță nouă, listă de bifat, scanare și bon — dintr-o atingere.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
    ])
  }
}

@main
struct NotiteWidgets: WidgetBundle {
  var body: some Widget {
    ListWidget()
    QuickWidget()
  }
}
