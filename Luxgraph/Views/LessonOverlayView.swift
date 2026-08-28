import SwiftUI

/// The speech-bubble card shown over the canvas while a lesson is active.
/// Ported from Modula's `LessonOverlayView` (Patch -> Graph).
struct LessonOverlayView: View {
    @EnvironmentObject var lessonViewModel: LessonViewModel

    var body: some View {
        if let lesson = lessonViewModel.activeLesson, lessonViewModel.currentStep != nil {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(lesson.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(stepCounterText(lesson: lesson))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button {
                            lessonViewModel.exit()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(lessonViewModel.narration)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.2), value: lessonViewModel.narration)

                    HStack {
                        Button {
                            lessonViewModel.back()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(lessonViewModel.isFirstStep)

                        Spacer()

                        Button {
                            lessonViewModel.next()
                        } label: {
                            Label(nextButtonTitle, systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                BubbleTail()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 10)
                    .offset(y: -1)
            }
            .padding(.horizontal, 16)
        }
    }

    private func stepCounterText(lesson: Lesson) -> String {
        var text = "Step \(lessonViewModel.stepIndex + 1) of \(lesson.steps.count)"
        if let progress = lessonViewModel.buildProgress {
            text += " · \(progress.current)/\(progress.total)"
        }
        return text
    }

    private var nextButtonTitle: String {
        if let progress = lessonViewModel.buildProgress, progress.current < progress.total {
            return "Next"
        }
        return lessonViewModel.isLastStep ? "Finish" : "Next"
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
