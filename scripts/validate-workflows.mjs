import {readFile, readdir} from "node:fs/promises";
import {pathToFileURL} from "node:url";

// Install @actions/workflow-parser in CI's temporary directory, keeping package
// dependencies out of the application and Homebrew formula.
const {parseWorkflow, convertWorkflowTemplate, NoOperationTraceWriter} = await import(
  pathToFileURL(process.env.WORKFLOW_PARSER_PATH).href
);

const directory = ".github/workflows";
for (const file of (await readdir(directory)).filter(name => /\.ya?ml$/.test(name)).sort()) {
  const name = `${directory}/${file}`;
  const content = await readFile(name, "utf8");
  const {context, value} = parseWorkflow({name, content}, new NoOperationTraceWriter());
  if (value) await convertWorkflowTemplate(context, value);
  const errors = context.errors.getErrors();
  if (errors.length > 0) {
    for (const error of errors) console.error(`${name}: ${error.message}`);
    process.exitCode = 1;
  } else {
    console.log(`${name}: valid`);
  }
}
