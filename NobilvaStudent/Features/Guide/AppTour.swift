import SwiftUI

/// 「使い方」ツアー。実際のタブ画面を切り替えながら、対象部分だけを
/// くり抜いて吹き出しで説明する。初回ログイン時に自動で始まり、
/// マイページ > 使い方 からいつでも再表示できる。
///
/// 仕組み:
///  - 各画面は `.tourTarget(_:)` で「ここを指せる」という目印を付け、
///    ウィンドウ座標の frame を `TourGeometry` に報告する。
///  - `MainTabView` の上に `TourOverlay` を被せ、現在のステップの frame を
///    読んで暗幕 + くり抜きを描く。
///  - anchorPreference は TabView / toolbar を越えて伝わらないため、
///    座標を共有ストアに集める方式にしている。
///  - 計画や先生がまだ無い生徒でも場所を指せるよう、ツアー中だけ `TourSample` の
///    見本を出す。ツアー中は暗幕が操作を止めるので、見本が送信されることはない。

/// ツアーで指し示す場所。`.id()` にも使うので Hashable。
enum TourTarget: String, Hashable {
    case todayFocus
    case todayNextUp
    case todayAddButton
    case todayTimerButton
    case chatFirstContact
    case myPageWeek
    case myPageStats
    case myPageBusySlots
    case myPageGuide
}

struct TourStep {
    let tab: MainTabView.Tab
    /// nil のときは画面中央に吹き出しだけ出す (くり抜き無し)。
    let target: TourTarget?
    let title: String
    let message: String

    static let all: [TourStep] = [
        TourStep(tab: .today, target: nil,
                 title: "Nobilva へようこそ",
                 message: "よく使う画面と操作を順番に紹介します。「次へ」で進めてください。"),
        TourStep(tab: .today, target: .todayFocus,
                 title: "まずはこれ",
                 message: "いちばん先に取り組むことが大きく表示されます。「取り組む」でタイマーを開始し、終わったら「完了」を押します。右端のボタンからは、その内容について先生に相談できます。"),
        TourStep(tab: .today, target: .todayNextUp,
                 title: "次にやること",
                 message: "残りのやることが並びます。左の丸で完了、行をタップするとタイマーが開きます。長押しすると、先生への相談や編集ができます。"),
        TourStep(tab: .today, target: .todayAddButton,
                 title: "タスクを追加",
                 message: "宿題や自分で進めたいことは、ここからタスクとして登録できます。"),
        TourStep(tab: .today, target: .todayTimerButton,
                 title: "タイマー",
                 message: "計画にないことを勉強するときや、計画を終えたあとに自習するときは、ここからタイマーを開いて時間を記録できます。"),
        TourStep(tab: .chat, target: .chatFirstContact,
                 title: "チャット",
                 message: "担当の先生ごとにカードが並びます。開くとチャットができ、その先生との次の面談も確認できます。"),
        TourStep(tab: .myPage, target: .myPageWeek,
                 title: "1 週間の計画",
                 message: "これからの 1 週間の計画が並びます。日付をタップすると、その日の計画を開けます。"),
        TourStep(tab: .myPage, target: .myPageStats,
                 title: "学習記録",
                 message: "タイマーで記録した学習時間を、数字とグラフで確認できます。"),
        TourStep(tab: .myPage, target: .myPageBusySlots,
                 title: "使えない時間",
                 message: "部活や塾など、勉強できない時間を登録しておくと、先生が計画を立てるときに避けてくれます。"),
        TourStep(tab: .myPage, target: .myPageGuide,
                 title: "案内はここから見直せます",
                 message: "この案内は「マイページ > 使い方」からいつでももう一度表示できます。"),
    ]
}

/// ツアーの進行状態。画面側は `current` を見てスクロールなどを行う。
@MainActor
final class TourController: ObservableObject {
    /// nil = ツアー非表示。
    @Published private(set) var index: Int?
    let geometry = TourGeometry()
    /// 見たかどうかは生徒ごとに覚える (同じ端末を別の生徒が使うこともあるため)。
    var userId: String?

    private var completedKey: String { "tour.completed.v1.\(userId ?? "-")" }
    private var signOutObserver: NSObjectProtocol?

    var steps: [TourStep] { TourStep.all }
    var current: TourStep? { index.map { steps[$0] } }
    var isActive: Bool { index != nil }

    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    init() {
        // ツアー中に強制ログアウトされても、次のログインに途中のツアーを持ち越さない。
        signOutObserver = NotificationCenter.default.addObserver(
            forName: .userDidSignOut, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.geometry.isPublishing = false
                self?.index = nil
                self?.userId = nil
            }
        }
    }

    func start() {
        geometry.isPublishing = true
        withAnimation(.easeInOut(duration: 0.25)) { index = 0 }
    }

    func next() {
        guard let index else { return }
        if index + 1 < steps.count {
            withAnimation(.spring(duration: 0.35)) { self.index = index + 1 }
        } else {
            finish()
        }
    }

    func back() {
        guard let index, index > 0 else { return }
        withAnimation(.spring(duration: 0.35)) { self.index = index - 1 }
    }

    /// 最後まで見た / スキップした のどちらでも完了扱い (初回自動表示は 1 度きり)。
    func finish() {
        UserDefaults.standard.set(true, forKey: completedKey)
        geometry.isPublishing = false
        withAnimation(.easeInOut(duration: 0.25)) { index = nil }
    }
}

/// 目印の frame (ウィンドウ座標) を集める。スクロールのたびに更新されるので、
/// ツアー表示中だけ変更を通知し、それ以外は黙って保持だけする
/// (常に通知すると購読している画面全体が毎フレーム再描画されるため)。
///
/// 別タブに隠れた画面は frame を消さずに「非表示」とだけ記録する。
/// 再表示されても位置が同じなら onGeometryChange は呼ばれないため、
/// 消してしまうとタブを戻ったときに対象を指せなくなる。
///
/// 表示中かどうかは、同じ目印を持つビューの数で数える。読み込みで見本 → 本物のように
/// ビューが入れ替わると、新しい方の onAppear が古い方の onDisappear より先に
/// 呼ばれることがあり、真偽値だと最後の「非表示」で上書きされてくり抜きが消えるため。
@MainActor
final class TourGeometry: ObservableObject {
    private var frames: [TourTarget: CGRect] = [:]
    private var visibleCount: [TourTarget: Int] = [:]
    var isPublishing = false {
        didSet { if isPublishing { objectWillChange.send() } }
    }

    func frame(of target: TourTarget) -> CGRect? {
        (visibleCount[target] ?? 0) > 0 ? frames[target] : nil
    }

    func set(_ target: TourTarget, _ frame: CGRect) {
        guard frames[target] != frame else { return }
        if isPublishing { objectWillChange.send() }
        frames[target] = frame
    }

    func setVisible(_ target: TourTarget, _ visible: Bool) {
        let old = visibleCount[target] ?? 0
        let new = max(0, old + (visible ? 1 : -1))
        visibleCount[target] = new
        if isPublishing, (old > 0) != (new > 0) { objectWillChange.send() }
    }
}

// MARK: - Target modifier

extension View {
    /// ツアーで指し示す対象として登録する。nil なら何もしない。
    func tourTarget(_ target: TourTarget?) -> some View {
        modifier(TourTargetModifier(target: target))
    }
}

private struct TourTargetModifier: ViewModifier {
    @EnvironmentObject var tour: TourController
    let target: TourTarget?

    func body(content: Content) -> some View {
        if let target {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    tour.geometry.set(target, frame)
                }
                .onAppear { tour.geometry.setVisible(target, true) }
                .onDisappear { tour.geometry.setVisible(target, false) }
        } else {
            content
        }
    }
}

// MARK: - Overlay

struct TourOverlay: View {
    @ObservedObject var tour: TourController
    @ObservedObject private var geometry: TourGeometry

    init(tour: TourController) {
        self.tour = tour
        self.geometry = tour.geometry
    }

    var body: some View {
        if let index = tour.index {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let step = tour.steps[index]
                let hole = spotlightRect(for: step, origin: origin, bounds: proxy.size)
                ZStack {
                    dimLayer(hole: hole)
                    if let hole {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                    }
                    bubble(step: step, index: index, hole: hole, size: proxy.size, safeArea: proxy.safeAreaInsets)
                }
                .animation(.spring(duration: 0.35), value: hole)
            }
            .ignoresSafeArea()
            // VoiceOver でも下の画面に移らず、吹き出しだけを読ませる。
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .transition(.opacity)
        }
    }

    /// 対象の frame を overlay 座標に直し、少し余白を足す。画面外なら nil。
    private func spotlightRect(for step: TourStep, origin: CGPoint, bounds: CGSize) -> CGRect? {
        guard let target = step.target, let global = geometry.frame(of: target) else { return nil }
        let rect = global.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
        let visible = CGRect(origin: .zero, size: bounds)
        guard rect.intersects(visible) else { return nil }
        return rect.intersection(visible.insetBy(dx: 4, dy: 4))
    }

    private func dimLayer(hole: CGRect?) -> some View {
        Rectangle()
            .fill(.black.opacity(0.6))
            .mask {
                Rectangle()
                    .overlay {
                        if let hole {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: hole.width, height: hole.height)
                                .position(x: hole.midX, y: hole.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .accessibilityHidden(true)
            // ツアー中は下の画面を触れないようにする (説明に集中してもらう)。
            .contentShape(Rectangle())
            .onTapGesture {}
    }

    /// 吹き出しは対象の上下で空いている方に置く。どちらも狭い (対象が大きい)
    /// ときは画面下部に重ねる。対象が無ければ中央。
    @ViewBuilder
    private func bubble(step: TourStep, index: Int, hole: CGRect?, size: CGSize, safeArea: EdgeInsets) -> some View {
        let card = TourBubble(step: step, index: index, total: tour.steps.count,
                              onBack: tour.back, onNext: tour.next, onSkip: tour.finish)
            .padding(.horizontal, 16)
        let minSpace: CGFloat = 230
        if let hole {
            let spaceAbove = hole.minY - safeArea.top
            let spaceBelow = size.height - hole.maxY - safeArea.bottom
            if spaceBelow >= minSpace && spaceBelow >= spaceAbove {
                card.frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, hole.maxY + 12)
            } else if spaceAbove >= minSpace {
                card.frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, size.height - hole.minY + 12)
            } else {
                card.frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, safeArea.bottom + 70)
            }
        } else {
            card.frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct TourBubble: View {
    let step: TourStep
    let index: Int
    let total: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isLast: Bool { index == total - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(index + 1) / \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if !isLast {
                    Button("スキップ", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.title)
                .font(.headline)
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if index > 0 {
                    Button("戻る", action: onBack)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(isLast ? "完了" : "次へ", action: onNext)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: 440)
        // ダークモードでは暗幕と背景色が近く沈んで見えるので、一段明るい面と縁取りで浮かせる。
        .background(colorScheme == .dark ? Color(UIColor.tertiarySystemGroupedBackground) : Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .id(index)
        .transition(.opacity)
    }
}

// MARK: - Sample

/// 計画や先生がまだ無いときに、ツアー中だけ出す見本。
enum TourSample {
    private static let idPrefix = "tour-sample-"

    static func isSample(_ item: StudyItem) -> Bool { item.id.hasPrefix(idPrefix) }

    static let focus = item(1, title: "教科書 p.24〜27（例題5問）", subject: "数学", start: "16:00", minutes: 30,
                            note: "これは見本です。先生が計画を立てると、ここに表示されます。")

    static let nextUp = [
        item(2, title: "英単語 Unit 3（30語）", subject: "英語", start: "17:00", minutes: 20),
        item(3, title: "理科 ワーク p.12", subject: "理科", start: "19:00", minutes: 30),
    ]

    static let contact = ChatContact(
        id: idPrefix + "contact", teacherId: nil, threadId: nil, name: "先生 (見本)",
        lastBody: "わからないところがあれば、いつでも聞いてくださいね。", lastAt: nil, unread: 0
    )

    private static func item(_ n: Int, title: String, subject: String, start: String, minutes: Int,
                             note: String? = nil) -> StudyItem {
        StudyItem(planItem: PlanItem(
            id: idPrefix + "\(n)", planId: "", taskId: nil, goalId: nil, title: title, subject: subject,
            startTime: start, durationMinutes: minutes, status: .pending, rationale: note, sortOrder: n
        ), date: nil)
    }
}
