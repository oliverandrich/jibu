defmodule Jibu.Credo.NoBeanIds do
  @moduledoc false
  use Credo.Check,
    id: "JIB001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Bean ids belong in the local tracker, which is not part of the repository.

      An id in the tree points at a ticket other clones never see.
      Write out the reasoning the id stands for, or drop the reference.
      """
    ]

  # The prefix is assembled so this file does not report itself.
  # The lookaheads skip longer names, file names and string literals that share the prefix.
  # A trailing period alone still counts, because a reference may end a sentence.
  @pattern Regex.compile!("jibu" <> "-[a-z0-9]{4}" <> "(?![a-z0-9-])" <> "(?!\\.\\S)" <> "(?!\")")

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.lines()
    |> Enum.flat_map(fn {line_no, line} ->
      @pattern
      |> Regex.scan(line)
      |> Enum.map(fn [match] -> issue_for(issue_meta, line_no, match) end)
    end)
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message: "Bean id in the tree. Write out what it stands for, or drop it.",
      line_no: line_no,
      trigger: trigger
    )
  end
end
