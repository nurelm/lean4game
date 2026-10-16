import { useAtom } from "jotai"
import { editorAtom, leanMonacoAtom, typewriterModeAtom } from "../../store/editor-atoms"
import React, { useEffect, useLayoutEffect, useRef } from "react"
import { ExerciseStatement } from "./ExerciseStatement"
import { Typewriter } from "./typewriter/Typewriter"
import { GameInfoview } from "./GameInfoview"

/**
 * Note: It is important that the `div` with `codeViewRef` is
 * always present, or the monaco editor cannot start.
 */
export function GameEditor({ codeviewRef } : { codeviewRef: React.MutableRefObject<HTMLDivElement> }) {
  const infoviewRef = useRef<HTMLDivElement>(null)
  const [leanMonaco] = useAtom(leanMonacoAtom)
  const [editor] = useAtom(editorAtom)
  const [typewriterMode] = useAtom(typewriterModeAtom)

  useLayoutEffect(() => {
    leanMonaco?.setInfoviewElement(infoviewRef.current!)
  })

  // Clicks in the editor should focus it. Re-asserting this on every mousedown
  // guards against races in monaco's own mousedown handling, which can leave
  // the editor unfocused (e.g. with synthetic clicks). The focus is re-asserted
  // in a timeout, since synthetic click handlers (cypress) blur the focused
  // element again right after the mousedown when the target has no focusable
  // ancestor.
  useEffect(() => {
    const el = codeviewRef.current
    if (!el) return
    const focusEditor = () => {
      editor?.focus()
      setTimeout(() => { editor?.focus() }, 0)
    }
    el.addEventListener("mousedown", focusEditor, true)
    return () => el.removeEventListener("mousedown", focusEditor, true)
  }, [editor])

  return <>
    <ExerciseStatement showLeanStatement={true} />
    <div ref={codeviewRef} className='codeview' />
    <div className='infoview' ref={infoviewRef}>
      {/* The game's own goal panel, shown instead of the VS Code-style webview. */}
      <GameInfoview />
    </div>
    {typewriterMode && <Typewriter />}
  </>
}
