import re

with open('firmware/main/SystemState.cpp', 'r') as f:
    content = f.read()

# Remove static bools from evaluateSafetyLoop
content = re.sub(r'\s*static bool temp_latch_danger = false;\n', '\n', content)
content = re.sub(r'\s*static bool mq2_latch_danger = false;\n', '\n', content)

# Add them to namespace scope
insertion = """
bool manual_sprinkler = false;
bool catastrophic_latch = false;
String active_triggers_json = "[]";

static bool temp_latch_danger = false;
static bool mq2_latch_danger = false;
"""
content = content.replace('\nbool manual_sprinkler = false;\nbool catastrophic_latch = false;\nString active_triggers_json = "[]";\n', insertion)

# Add transition logic for manual_sprinkler reset on mq2 danger
mq2_logic = """
    bool prev_mq2_latch = mq2_latch_danger;
    if (in_mq2_danger) {
        mq2_latch_danger = true;
    } else if (!is_mq2_fault && current_mq2_v <= threshold_mq2_v * 0.95f) {
        mq2_latch_danger = false;
    }
    
    if (mq2_latch_danger && !prev_mq2_latch) {
        manual_sprinkler = false;
    }
"""

content = re.sub(r'\n\s*if \(in_mq2_danger\) \{[\s\S]*?mq2_latch_danger = false;\n\s*\}', mq2_logic, content)

with open('firmware/main/SystemState.cpp', 'w') as f:
    f.write(content)
