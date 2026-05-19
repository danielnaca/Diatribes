import Combine
import SwiftUI

// MARK: - Topic model

struct LessonTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let subtitle: String
}

private let frenchTopics: [LessonTopic] = [
    LessonTopic(id: "adj",       title: "Adjective Agreement",  emoji: "🎨", subtitle: "Gender & number matching"),
    LessonTopic(id: "negation",  title: "French Negation",       emoji: "🚫", subtitle: "ne…pas & friends"),
    LessonTopic(id: "passe",     title: "Passé Composé",         emoji: "⏪", subtitle: "Past tense & auxiliaries"),
    LessonTopic(id: "imparfait", title: "The Imparfait",         emoji: "🌊", subtitle: "Background & habits"),
    LessonTopic(id: "subj",      title: "The Subjunctive",       emoji: "💭", subtitle: "Doubt, wishes, emotions"),
    LessonTopic(id: "futur",     title: "Future Tense",          emoji: "🚀", subtitle: "Simple & near future"),
    LessonTopic(id: "avoir-etre",title: "Être & Avoir",          emoji: "🔑", subtitle: "The two essential verbs"),
    LessonTopic(id: "questions", title: "Questions",             emoji: "❓", subtitle: "Inversion & est-ce que"),
]

private let spanishTopics: [LessonTopic] = [
    LessonTopic(id: "ser-estar",  title: "Ser vs Estar",          emoji: "🔑", subtitle: "Permanent vs temporary"),
    LessonTopic(id: "preterite",  title: "Preterite Tense",       emoji: "⏪", subtitle: "Completed past actions"),
    LessonTopic(id: "imperfect",  title: "The Imperfect",         emoji: "🌊", subtitle: "Ongoing past & habits"),
    LessonTopic(id: "subj",       title: "The Subjunctive",       emoji: "💭", subtitle: "Wishes, doubt, emotions"),
    LessonTopic(id: "adj",        title: "Adjective Agreement",   emoji: "🎨", subtitle: "Gender & number"),
    LessonTopic(id: "gustar",     title: "Gustar & Friends",      emoji: "❤️", subtitle: "Backwards-feeling verbs"),
    LessonTopic(id: "future",     title: "Future Tense",          emoji: "🚀", subtitle: "Simple & going-to"),
    LessonTopic(id: "reflexive",  title: "Reflexive Verbs",       emoji: "🔄", subtitle: "Se lavar, levantarse…"),
]

// MARK: - Daily insights

struct Insight {
    let text: String
    let detail: String
}

private let frenchInsights: [Insight] = [
    Insight(text: "Manquer works backwards", detail: "\"Tu me manques\" means \"I miss you\" — literally \"you are lacking to me\". The subject and object are flipped from English."),
    Insight(text: "Two verbs for \"to know\"", detail: "Savoir is for facts and skills (Je sais nager). Connaître is for people and places (Je connais Paris). They're never interchangeable."),
    Insight(text: "Adjectives usually follow the noun", detail: "Une maison rouge. But BAGS adjectives (Beauty, Age, Goodness, Size) go before: une belle maison, un vieux livre. Some change meaning based on position."),
    Insight(text: "Dr & Mrs Vandertramp", detail: "These 16 verbs take être as their auxiliary in the passé composé: Devenir, Revenir, Monter, Rentrer, Sortir, Venir, Aller, Naître, Descendre, Entrer, Rester, Tomber, Retourner, Arriver, Mourir, Partir. All others take avoir."),
    Insight(text: "70, 80, 90 are wild", detail: "French numbers: 70 = soixante-dix (sixty-ten), 80 = quatre-vingts (four-twenties), 90 = quatre-vingt-dix. Belgian French sensibly says septante, octante, nonante instead."),
    Insight(text: "You \"have\" an age in French", detail: "J'ai vingt ans — literally \"I have twenty years\". You also \"have\" hunger (faim), thirst (soif), fear (peur), heat (chaud), and cold (froid) rather than \"being\" them."),
    Insight(text: "The conditional is two tenses in one", detail: "French conditional = future stem + imperfect endings. Aller → ir- + ais → irais. Once you know your future stems and imperfect endings, conditional is free."),
]

private let spanishInsights: [Insight] = [
    Insight(text: "Gustar works backwards", detail: "\"Me gusta el café\" = \"I like coffee\" — literally \"coffee pleases to me\". The verb agrees with coffee (the subject), not with you. Me gustan los libros."),
    Insight(text: "DOCTOR vs PLACE for ser & estar", detail: "Use ser for: Description, Occupation, Characteristic, Time, Origin, Relationship. Use estar for: Position, Location, Action, Condition, Emotion."),
    Insight(text: "Preterite vs Imperfect is conceptual", detail: "It's not about time — it's about how you view the action. Preterite = completed, bounded event. Imperfect = ongoing state, habit, or background description."),
    Insight(text: "-tion words are free vocabulary", detail: "Over 90% of English words ending in -tion become -ción in Spanish with the same meaning: nation→nación, innovation→innovación, action→acción, revolution→revolución."),
    Insight(text: "Reflexive verbs aren't always reflexive", detail: "Se lavar means to wash oneself — but dormirse means to fall asleep (not to put yourself to sleep). Many reflexives encode a change of state rather than doing something to yourself."),
    Insight(text: "WEIRDO triggers the subjunctive", detail: "Wishes, Emotion, Impersonal expressions, Requests, Doubt/Denial, Ojalá — these signal the subjunctive in the dependent clause. Quiero que vengas. Es importante que estudies."),
    Insight(text: "Yo forms are uniquely irregular", detail: "Spanish verbs are most irregular in the yo (first person singular) present: pongo, tengo, hago, salgo, conozco, sé, doy, voy. Memorise the yo form and the rest often follows a pattern."),
]

// MARK: - ViewModel

@MainActor
final class StudyViewModel: ObservableObject {
    @AppStorage("language") var language = "French"

    var topics: [LessonTopic] { language == "Spanish" ? spanishTopics : frenchTopics }
    var insights: [Insight] { language == "Spanish" ? spanishInsights : frenchInsights }

    var todayInsight: Insight {
        let day = Calendar.current.component(.weekday, from: Date()) - 1
        return insights[day % insights.count]
    }

    // Lesson
    @Published var lesson: LessonContent?
    @Published var lessonLoading = false
    @Published var lessonFailed = false
    @Published var activeTopic: LessonTopic?

    // Quiz
    @Published var quiz: StudyQuiz?
    @Published var quizLoading = false
    @Published var quizTopic: String?

    // Conjugation explore
    @Published var conjugation: ConjugationResult?
    @Published var conjugationLoading = false
    @Published var conjugationFailed = false

    func loadLesson(_ topic: LessonTopic) async {
        activeTopic = topic
        lesson = nil
        lessonFailed = false
        lessonLoading = true
        do {
            lesson = try await APIClient.shared.studyLesson(topic: topic.title, language: language)
        } catch {
            lessonFailed = true
        }
        lessonLoading = false
    }

    func loadQuiz(topic: String? = nil) async {
        let t = topic ?? activeTopic?.title ?? "grammar"
        quizTopic = t
        quiz = nil
        quizLoading = true
        do {
            quiz = try await APIClient.shared.studyExercises(topic: t, language: language)
        } catch {}
        quizLoading = false
    }

    func loadConjugation(verb: String) async {
        guard !verb.isEmpty else { return }
        conjugation = nil
        conjugationFailed = false
        conjugationLoading = true
        do {
            conjugation = try await APIClient.shared.conjugate(verb: verb, language: language)
        } catch {
            conjugationFailed = true
        }
        conjugationLoading = false
    }
}

// MARK: - Root view

struct StudyView: View {
    @StateObject private var vm = StudyViewModel()
    @State private var subTab = 0
    @State private var selectedTopic: LessonTopic?
    @State private var showQuiz = false
    @State private var verbSearch = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                studyTabBar
                Divider()
                    .opacity(0.5)
                Group {
                    switch subTab {
                    case 0: learnTab
                    case 1: practiseTab
                    default: exploreTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedTopic) { topic in
                LessonSheet(topic: topic, onPractice: {
                    selectedTopic = nil
                    withAnimation { subTab = 1 }
                    if vm.activeTopic?.id == topic.id { showQuiz = true }
                })
                .environmentObject(vm)
            }
        }
        .environmentObject(vm)
    }

    // MARK: Tab bar

    private var studyTabBar: some View {
        HStack(spacing: 0) {
            studyTabButton("Learn", tag: 0)
            studyTabButton("Practise", tag: 1)
            studyTabButton("Explore", tag: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func studyTabButton(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { subTab = tag }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(subTab == tag ? Color(.systemGray5) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(subTab == tag ? .primary : .secondary)
    }

    // MARK: Learn tab

    private var learnTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                insightCard
                topicSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var insightCard: some View {
        let insight = vm.todayInsight
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                Text("Today's Insight")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(Color(red: 188/255, green: 130/255, blue: 0))

            Text(insight.text)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 188/255, green: 130/255, blue: 0).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lesson topics")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(vm.topics) { topic in
                    topicCard(topic)
                }
            }
        }
    }

    private func topicCard(_ topic: LessonTopic) -> some View {
        Button {
            selectedTopic = topic
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(topic.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(topic.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Practise tab

    private var practiseTab: some View {
        Group {
            if vm.quizLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generating exercises…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let quiz = vm.quiz {
                QuizSessionView(quiz: quiz, language: vm.language) {
                    vm.quiz = nil
                }
            } else {
                quizSetupView
            }
        }
    }

    private var quizSetupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 188/255, green: 130/255, blue: 0))
                    Text("Quick Quiz")
                        .font(.title2.weight(.bold))
                    Text("Five questions on a topic of your choice.\nImmediate feedback and explanations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick a topic")
                        .font(.headline)
                        .padding(.horizontal, 16)

                    ForEach(vm.topics) { topic in
                        Button {
                            Task { await vm.loadQuiz(topic: topic.title) }
                        } label: {
                            HStack {
                                Text(topic.emoji)
                                    .font(.title3)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(topic.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(topic.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 68)
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.systemGray5)))
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: Explore tab

    private var exploreTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Enter a verb…", text: $verbSearch)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { conjugate() }
                    if !verbSearch.isEmpty {
                        Button { verbSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding()

                Button {
                    conjugate()
                } label: {
                    Text("Conjugate")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.primary)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(verbSearch.trimmingCharacters(in: .whitespaces).isEmpty || vm.conjugationLoading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color(.systemBackground))

            Divider()

            if vm.conjugationLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Conjugating…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.conjugationFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Couldn't conjugate that verb")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { conjugate() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = vm.conjugation {
                conjugationResultView(result)
            } else {
                explorePrompt
            }
        }
    }

    private var explorePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Enter any \(vm.language) verb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func conjugationResultView(_ result: ConjugationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Verb header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(result.verb)
                            .font(.title2.weight(.bold))
                        if result.irregular {
                            Text("irregular")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(result.english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ForEach(result.tenses, id: \.name) { tense in
                    inlineTenseBlock(tense)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func inlineTenseBlock(_ tense: ConjugationTense) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tense.name)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(tense.forms.enumerated()), id: \.offset) { index, form in
                    HStack {
                        Text(form.pronoun)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(form.form)
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(index % 2 == 0 ? Color.clear : Color(.systemGray6))
                }
            }
        }
    }

    private func conjugate() {
        let verb = verbSearch.trimmingCharacters(in: .whitespaces)
        guard !verb.isEmpty else { return }
        Task { await vm.loadConjugation(verb: verb) }
    }
}

// MARK: - Lesson sheet

struct LessonSheet: View {
    let topic: LessonTopic
    let onPractice: () -> Void

    @EnvironmentObject private var vm: StudyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.lessonLoading {
                    loadingView
                } else if vm.lessonFailed {
                    failureView
                } else if let lesson = vm.lesson, vm.activeTopic?.id == topic.id {
                    lessonContent(lesson)
                } else {
                    loadingView
                }
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationBackground(.white)
        .task { await vm.loadLesson(topic) }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Preparing lesson…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't load lesson")
                .font(.headline)
            Button("Try again") { Task { await vm.loadLesson(topic) } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lessonContent(_ lesson: LessonContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Hook
                Text(lesson.summary)
                    .font(.title3.weight(.medium))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                // Explanation
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Explanation")
                    Text(lesson.explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Examples
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Examples")
                    ForEach(lesson.examples.indices, id: \.self) { i in
                        exampleCard(lesson.examples[i])
                    }
                }

                // Key points
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Key points")
                    ForEach(lesson.key_points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.086, green: 0.639, blue: 0.239))
                                .font(.body)
                                .padding(.top, 1)
                            Text(point)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Insider tip
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption.weight(.bold))
                        Text("Insider Tip")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color(red: 188/255, green: 130/255, blue: 0))
                    Text(lesson.tip)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color(red: 188/255, green: 130/255, blue: 0).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Practice button
                Button {
                    Task {
                        await vm.loadQuiz(topic: topic.title)
                        onPractice()
                    }
                } label: {
                    Label("Practise this topic", systemImage: "brain.filled.head.profile")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }

    private func exampleCard(_ example: LessonExample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(example.foreign)
                .font(.body.weight(.medium))
            Text(example.english)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = example.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color(red: 188/255, green: 130/255, blue: 0))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Quiz session

struct QuizSessionView: View {
    let quiz: StudyQuiz
    let language: String
    let onDone: () -> Void

    @State private var current = 0
    @State private var selected: Int? = nil
    @State private var showExplanation = false
    @State private var correctCount = 0
    @State private var finished = false

    private var question: QuizQuestion { quiz.exercises[current] }
    private var total: Int { quiz.exercises.count }
    private let amber = Color(red: 188/255, green: 130/255, blue: 0)

    var body: some View {
        if finished {
            resultsView
        } else {
            questionView
        }
    }

    // MARK: Question

    private var questionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Progress
                VStack(spacing: 6) {
                    ProgressView(value: Double(current), total: Double(total))
                        .tint(amber)
                    Text("Question \(current + 1) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Question
                Text(question.question)
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                // Options
                VStack(spacing: 10) {
                    ForEach(question.options.indices, id: \.self) { i in
                        optionButton(index: i)
                    }
                }

                // Explanation
                if showExplanation {
                    explanationCard

                    Button {
                        advance()
                    } label: {
                        Text(current + 1 < total ? "Next →" : "See results")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .animation(.easeInOut(duration: 0.2), value: showExplanation)
    }

    private func optionButton(index: Int) -> some View {
        let isSelected = selected == index
        let isCorrect = index == question.correct
        let revealed = showExplanation

        let bg: Color = {
            guard revealed else { return isSelected ? Color(.systemGray5) : Color(.systemGray6) }
            if isCorrect { return Color(red: 0.086, green: 0.639, blue: 0.239).opacity(0.15) }
            if isSelected && !isCorrect { return Color.red.opacity(0.12) }
            return Color(.systemGray6)
        }()

        let border: Color = {
            guard revealed else { return isSelected ? .primary : .clear }
            if isCorrect { return Color(red: 0.086, green: 0.639, blue: 0.239) }
            if isSelected && !isCorrect { return .red }
            return .clear
        }()

        return Button {
            guard selected == nil else { return }
            selected = index
            if index == question.correct { correctCount += 1 }
            withAnimation { showExplanation = true }
        } label: {
            HStack(spacing: 12) {
                Text(["A", "B", "C", "D"][index])
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(revealed && isCorrect ? Color(red: 0.086, green: 0.639, blue: 0.239) : Color(.systemGray4))
                    .foregroundStyle(revealed && isCorrect ? .white : .secondary)
                    .clipShape(Circle())
                Text(question.options[index])
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if revealed {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.086, green: 0.639, blue: 0.239))
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(14)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(revealed)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: selected == question.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(selected == question.correct
                                     ? Color(red: 0.086, green: 0.639, blue: 0.239)
                                     : .red)
                Text(selected == question.correct ? "Correct!" : "Not quite")
                    .font(.subheadline.weight(.semibold))
            }
            Text(question.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Results

    private var resultsView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Text(scoreEmoji)
                    .font(.system(size: 64))
                Text("\(correctCount) / \(total)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text(scoreMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    resetQuiz()
                } label: {
                    Label("Try again", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button("Pick a new topic") { onDone() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var scoreEmoji: String {
        switch correctCount {
        case total: return "🏆"
        case let n where n >= total * 4 / 5: return "🎉"
        case let n where n >= total / 2: return "💪"
        default: return "📚"
        }
    }

    private var scoreMessage: String {
        switch correctCount {
        case total: return "Perfect score!"
        case let n where n >= total * 4 / 5: return "Really strong!"
        case let n where n >= total / 2: return "Good effort — keep going"
        default: return "Room to grow — review the lesson"
        }
    }

    private func advance() {
        if current + 1 < total {
            current += 1
            selected = nil
            showExplanation = false
        } else {
            finished = true
        }
    }

    private func resetQuiz() {
        current = 0
        selected = nil
        showExplanation = false
        correctCount = 0
        finished = false
    }
}
