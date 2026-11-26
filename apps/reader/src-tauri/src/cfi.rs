#[derive(Eq, Ord, PartialEq, PartialOrd)]
pub struct Position {
    pub start: Vec<Vec<(u32, u32)>>,
    pub end: Vec<Vec<(u32, u32)>>,
}

// The reader uses Foliate CFIs for both EPUB and other formats. Assertions
// refer to element IDs or text and don't affect book order.
pub fn position(locator: &str) -> Option<Position> {
    let inner = locator.strip_prefix("epubcfi(")?.strip_suffix(')')?;
    let mut path = String::new();
    let mut assertion = false;
    let mut escaped = false;
    for ch in inner.chars() {
        match ch {
            _ if escaped => escaped = false,
            '^' => escaped = true,
            '[' => assertion = true,
            ']' => assertion = false,
            _ if !assertion => path.push(ch),
            _ => {}
        }
    }
    if assertion || escaped {
        return None;
    }
    fn steps(path: &str) -> Option<Vec<Vec<(u32, u32)>>> {
        path.split('!')
            .map(|part| {
                part.strip_prefix('/')?
                    .split('/')
                    .map(|step| {
                        let (index, offset) = step.split_once(':').unwrap_or((step, "0"));
                        let offset = offset.split(['~', '@', ';']).next()?;
                        Some((index.parse().ok()?, offset.parse().ok()?))
                    })
                    .collect()
            })
            .collect()
    }

    let paths = path.split(',').collect::<Vec<_>>();
    let (start, end) = match paths.as_slice() {
        [point] => (steps(point)?, steps(point)?),
        [parent, start, end] => (
            steps(&format!("{parent}{start}"))?,
            steps(&format!("{parent}{end}"))?,
        ),
        _ => return None,
    };
    Some(Position { start, end })
}
