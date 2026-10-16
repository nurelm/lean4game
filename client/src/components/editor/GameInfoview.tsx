import * as React from "react"
import { useAtom } from "jotai"
import { useTranslation } from "react-i18next"
import { TaggedText_stripTags } from "@leanprover/infoview-api"
import { editorAtom, proofAtom, typewriterModeAtom } from "../../store/editor-atoms"
import { helpAtom, selectedStepAtom } from "../../store/chat-atoms"
import { Goal } from "./typewriter/proof_step/Goal"
import { Errors } from "./messages/Error"
import { Hints, filterHints } from "../hints"

/**
 * The game's own info panel, shown below the editor in editor mode. It displays
 * the goal at the cursor position, the game hints belonging to that goal, and
 * the remaining messages (e.g. "unsolved goals"). In typewriter mode the proof
 * steps and hints are shown in the proof panel and chat instead, so this
 * renders nothing.
 */
export function GameInfoview() {
  const { t } = useTranslation()
  const [editor] = useAtom(editorAtom)
  const [typewriterMode] = useAtom(typewriterModeAtom)
  const [proof] = useAtom(proofAtom)
  const [help] = useAtom(helpAtom)
  const [selectedStep, setSelectedStep] = useAtom(selectedStepAtom)

  // Track the cursor position to display the goal at that position.
  const [cursor, setCursor] = React.useState<{line: number, column: number} | undefined>(undefined)
  React.useEffect(() => {
    if (!editor) {
      setCursor(undefined)
      return
    }
    const update = () => {
      const pos = editor.getPosition()
      setCursor(pos ? {line: pos.lineNumber, column: pos.column} : undefined)
    }
    update()
    const disposable = editor.onDidChangeCursorPosition(update)
    return () => disposable.dispose()
  }, [editor])

  if (typewriterMode) return null
  if (!proof) return null

  // The steps of the proof follow the lines of the file: `steps[i]` is the state
  // at the beginning of the (1-based) line `i + 1`. At a cursor, we are at the
  // state before the current line's command (at the start of a line) or after
  // it (further right).
  const stepIndex = cursor === undefined
    ? 0
    : Math.max(0, Math.min(cursor.line - 1 + (cursor.column > 1 ? 1 : 0), proof.steps.length - 1))
  const step = proof.steps[stepIndex]
  if (!step) return null

  function toggleSelection(line: number) {
    return (ev: any) => {
      if (selectedStep == line) {
        setSelectedStep(undefined)
      } else {
        setSelectedStep(line)
      }
    }
  }

  const goal = step.goals[0]
  const filteredHints = filterHints(goal?.hints, proof.steps[stepIndex-1]?.goals[0]?.hints)

  return <div className="lean4game-infoview vscode-light">
    <div className="goals-section">
      <div className="goals-section-title">{t("Current Goal")}</div>
      {goal
        ? <Goal goal={goal.goal} />
        : <div className="goals-section-title">{t("No Goals")}</div>}
    </div>
    {goal &&
      <div className="message error">
        <div>unsolved goals</div>
        <pre className="font-code pre-wrap">⊢ {TaggedText_stripTags(goal.goal.type)}</pre>
      </div>}
    {goal && <Errors errors={step.diags} typewriterMode={false} />}
    {proof.diagnostics.length > 0 &&
      <Errors errors={proof.diagnostics} typewriterMode={false} />}
    <Hints hints={filteredHints} showHidden={help.has(stepIndex)} step={stepIndex}
      selected={selectedStep} toggleSelection={toggleSelection(stepIndex)} />
  </div>
}