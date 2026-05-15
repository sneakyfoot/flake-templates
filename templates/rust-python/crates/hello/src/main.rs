use pyo3::prelude::*;

fn main() -> PyResult<()> {
    Python::with_gil(|py| {
        let tools = py.import_bound("hello_tools")?;
        let result: String = tools.getattr("greet")?.call0()?.extract()?;
        println!("{}", result);
        Ok(())
    })
}
