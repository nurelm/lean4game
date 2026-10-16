// TODO: Should not use index as key.
import React from "react";

import { InteractiveDiagnostic, MsgEmbed, TaggedText } from "@leanprover/infoview-api";
import { DiagnosticSeverity } from "vscode-languageserver-types";

/**
 * Render a `TaggedText` message to plain text.
 *
 * Note that `TaggedText_stripTags` from the infoview API only follows the `tag[1]`
 * (the remainder of the string), but the Lean server sends the actual text inside
 * "expression" embeds (`tag[0] = {expr: ...}`), which would be dropped entirely.
 */
function messageToString(message: TaggedText<MsgEmbed>): string {
  const go = (t: any): string => {
    if (typeof t !== 'object' || t === null) return ''
    if ('append' in t) return t.append.reduce((acc, t_) => acc + go(t_), '')
    if ('tag' in t) {
      const [embed, rest] = t.tag
      return (embed && 'expr' in embed ? go(embed.expr) : '') + go(rest)
    }
    if ('text' in t) return t.text
    return ''
  }
  return go(message)
}

/** A list of messages (info/warning/error) that are produced after this command */
export function Errors ({errors, typewriterMode} : {errors : InteractiveDiagnostic[], typewriterMode : boolean}) {
  return <div>
    {errors.map((err, i) => (<Error key={`error-${i}`} error={err} typewriterMode={typewriterMode}/>))}
  </div>
}

/** A list of messages (info/warning/error) that are produced after this command */
function Error({error, typewriterMode} : {error : InteractiveDiagnostic, typewriterMode : boolean}) {
  // The first step will always have an empty command

  const severityClass = error.severity ? {
    [DiagnosticSeverity.Error]: 'error',
    [DiagnosticSeverity.Warning]: 'warning',
    [DiagnosticSeverity.Information]: 'information',
    [DiagnosticSeverity.Hint]: 'hint',
  }[error.severity] : '';

  const {line, character} = error.range.start;
  const title = `Line ${line+1}, Character ${character}`;

  // Hide "unsolved goals" messages
  let message: TaggedText<MsgEmbed>;
  const firstText = ("append" in error.message && error.message.append.length > 0)
    ? messageToString(error.message.append[0]) : null
  if (firstText !== null &&
  firstText.startsWith("unsolved goals")) {
      message = error.message.append[0]
  } else {
      message = error.message
  }

  const messageString = messageToString(message);

  return (messageString.trim().length > 0 && (
  <div className={severityClass + ' ml1 message'}>
    {!typewriterMode && <p className="mv2">{title}</p>}
    <pre className="font-code pre-wrap">
      <p>{messageString}</p>
    </pre>
  </div>
  ))
}
