//
//  SessionQuestionDock.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Full-screen overlay dock that presents a batch of questions from the agent.
/// Shows one question at a time with progress segments, option selection,
/// custom input, and Next/Back/Submit/Reject navigation.
struct SessionQuestionDock: View {
    let request: QuestionRequest
    let viewModel: ChatViewModel

    @State private var currentIndex: Int = 0
    @State private var answers: [[String]] = []
    @State private var customInputs: [String] = []
    @State private var isSubmitting: Bool = false
    /// Tracks navigation direction for slide transition.
    @State private var navigatingForward: Bool = true

    private var currentQuestion: QuestionInfo {
        request.questions[currentIndex]
    }

    private var isLastQuestion: Bool {
        currentIndex == request.questions.count - 1
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Theme.Colors.scrim
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss keyboard only — do NOT reject
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }

            // Card
            VStack(spacing: Theme.Spacing.md) {
                // A. Header
                headerRow

                // B. Progress segments
                if request.questions.count > 1 {
                    progressSegments
                }

                // C + D + E. Question content (animated)
                questionContent
                    .id(currentIndex)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: navigatingForward ? .trailing : .leading),
                            removal: .move(edge: navigatingForward ? .leading : .trailing)
                        )
                    )

                // F. Navigation buttons
                navigationButtons
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 20).fill(Theme.Colors.glassFill))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.Colors.border, lineWidth: 1))
                    .shadow(color: Theme.Colors.shadow, radius: 12)
            )
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .onAppear {
            if answers.isEmpty {
                answers = Array(repeating: [], count: request.questions.count)
            }
            if customInputs.isEmpty {
                customInputs = Array(repeating: "", count: request.questions.count)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.Colors.neonOrange)

            Text("Question")
                .font(.headline)
                .foregroundStyle(Theme.Colors.cloud)

            Spacer()

            Text("\(currentIndex + 1) of \(request.questions.count)")
                .font(.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
    }

    // MARK: - Progress Segments

    private var progressSegments: some View {
        HStack(spacing: 4) {
            ForEach(request.questions.indices, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(for: index))
                    .frame(height: 4)
                    .onTapGesture {
                        let forward = index > currentIndex
                        navigatingForward = forward
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentIndex = index
                        }
                    }
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        if index == currentIndex {
            return Theme.Colors.cyberBlue
        }
        let hasAnswer = (answers.indices.contains(index) && !answers[index].isEmpty)
            || (customInputs.indices.contains(index) && !customInputs[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return hasAnswer ? Theme.Colors.neonGreen.opacity(0.5) : Theme.Colors.graphite
    }

    // MARK: - Question Content

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // C. Header + text
            Text(currentQuestion.header)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.Colors.cloud)

            Text(currentQuestion.question)
                .font(.caption)
                .foregroundStyle(Theme.Colors.silver)
                .fixedSize(horizontal: false, vertical: true)

            // D. Options
            if !currentQuestion.options.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(currentQuestion.options, id: \.self) { option in
                            optionRow(option)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            // E. Custom input
            if currentQuestion.allowsCustom {
                TextField("Type your own answer…", text: bindingForCustom(currentIndex))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.cloud)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(Theme.Colors.carbon)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Option Row

    private func optionRow(_ option: QuestionOption) -> some View {
        let isSelected = answers.indices.contains(currentIndex)
            ? answers[currentIndex].contains(option.label)
            : false

        return Button {
            toggleOption(option.label)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Theme.Colors.neonGreen : Theme.Colors.silver)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.cloud)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.smoke)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Theme.Colors.graphite.opacity(isSelected ? 0.6 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func toggleOption(_ label: String) {
        guard answers.indices.contains(currentIndex) else { return }
        if currentQuestion.allowsMultiple {
            if let existing = answers[currentIndex].firstIndex(of: label) {
                answers[currentIndex].remove(at: existing)
            } else {
                answers[currentIndex].append(label)
            }
        } else {
            if answers[currentIndex].contains(label) {
                answers[currentIndex] = []
            } else {
                answers[currentIndex] = [label]
            }
        }
    }

    // MARK: - Custom Input Binding

    private func bindingForCustom(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard customInputs.indices.contains(index) else { return "" }
                return customInputs[index]
            },
            set: { value in
                guard customInputs.indices.contains(index) else { return }
                customInputs[index] = value
            }
        )
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Reject
            Button {
                reject()
            } label: {
                Text("Reject")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.hotPink)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.hotPink.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.Colors.hotPink.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .disabled(isSubmitting)

            Spacer()

            // Back
            if currentIndex > 0 {
                Button {
                    navigatingForward = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentIndex -= 1
                    }
                } label: {
                    Text("Back")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.Colors.graphite)
                        )
                }
            }

            // Next / Submit
            Button {
                if isLastQuestion {
                    submit()
                } else {
                    navigatingForward = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentIndex += 1
                    }
                }
            } label: {
                Text(isSubmitting ? "Sending…" : (isLastQuestion ? "Submit" : "Next"))
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.cyberBlue)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.cyberBlue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.Colors.cyberBlue.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .disabled(isSubmitting)
        }
    }

    // MARK: - Actions

    private func buildFinalAnswers() -> [QuestionAnswer] {
        request.questions.indices.map { index in
            var merged = answers.indices.contains(index) ? answers[index] : []
            let custom = customInputs.indices.contains(index)
                ? customInputs[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            if !custom.isEmpty && !merged.contains(custom) {
                merged.append(custom)
            }
            return merged
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let finalAnswers = buildFinalAnswers()
                try await viewModel.replyToQuestion(request, answers: finalAnswers)
            } catch {
                viewModel.error = error.localizedDescription
            }
        }
    }

    private func reject() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await viewModel.rejectQuestion(request)
            } catch {
                viewModel.error = error.localizedDescription
            }
        }
    }
}
