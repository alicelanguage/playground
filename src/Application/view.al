using System.Net

namespace Alice.Playground
  module View
    def self.Escape(text : String) : String
      WebUtility.HtmlEncode(text)
    end

    # Example ids and labels, in menu order (the first is the default program).
    def self.Examples() : Array(String)
      ["pipeline|Iterator pipeline", "fibonacci|Fibonacci", "patterns|Pattern matching", "classes|Classes & properties", "collections|Strings & collections", "parallel|Parallel map", "types|Records & .NET", "safety|Immutable bindings"]
    end

    def self.Example(name : String) : String
      case name
      when "fibonacci"
        "# Functions, recursion, and inferred types\ndef fibonacci(n : Int32) : Int32\n  return n if n < 2\n  fibonacci(n - 1) + fibonacci(n - 2)\nend\n\nfor i in 0...12\n  puts fibonacci(i)\nend\n"
      when "types"
        "# Alice types on the .NET runtime\nrecord Point(x : Float64, y : Float64)\n\ndef distance(p : Point) : Float64\n  Math.Sqrt(p.x * p.x + p.y * p.y)\nend\n\np = Point.new(3.0, 4.0)\nputs p\nputs distance(p)\n"
      when "safety"
        "# val bindings are immutable. Try changing val to var.\nval answer = 41\nanswer = 42\nputs answer\n"
      when "patterns"
        "# Pattern matching with case/in and case/when\ndef describe(value : Object) : String\n  case value\n  when Int32 then \"an integer\"\n  when String then \"a string\"\n  else \"something curious\"\n  end\nend\n\ndef classify(n : Int32) : String\n  case n\n  when 0 then \"zero\"\n  when 1..9 then \"small\"\n  else \"large\"\n  end\nend\n\nputs describe(42)\nputs describe(\"rabbit\")\n[0, 7, 120].each { |n| puts \"\#{n} is \#{classify(n)}\" }\n"
      when "classes"
        "# Classes, properties and string interpolation\nclass Rabbit\n  getter name : String\n  property late : Bool = true\n\n  def initialize(@name : String)\n  end\n\n  def greet : String\n    late ? \"\#{name}: I'm late, I'm late!\" : \"\#{name}: right on time.\"\n  end\nend\n\nwhite = Rabbit.new(\"White Rabbit\")\nputs white.greet\nwhite.late = false\nputs white.greet\n"
      when "parallel"
        "# Data-parallel map: pure blocks may run on every core\nsquares = (1..10).to_a.par_map { |x| x * x }\nputs squares.join(\", \")\nsquares.sum\n"
      when "collections"
        "# Strings, symbols and collections\nwords = [\"curiouser\", \"and\", \"curiouser\"]\ncounts = Hash(String, Int32).new\nwords.each { |w| counts[w] = counts.fetch(w, 0) + 1 }\ncounts.each { |k, v| puts \"\#{k.upcase} × \#{v}\" }\nputs words.map { |w| w.capitalize }.join(\" \")\ncounts.size\n"
      else
        "# A little Alice. All the way down to IL.\nxs = [1, 2, 3, 4, 5]\n\n# This pipeline becomes a loop in MIR.\nresult = xs.map { |x| x * x }.sum\n\nputs \"Hello from Alice!\"\nresult\n"
      end
    end

    def self.Result(result : PlaygroundResult, stage : String) : String
      code = case stage
      when "hir" then result.Hir
      when "mir" then result.Mir
      when "il" then result.Il
      else result.CSharp
      end
      code = "This stage is unavailable. See the diagnostic below." if code.Length == 0
      messages = StringBuilder.new
      for diagnostic in result.Diagnostics
        messages.Append("<button class=diagnostic data-line=\"#{diagnostic.Line}\" data-col=\"#{diagnostic.Col}\"><span>#{Escape(diagnostic.Code)} · #{diagnostic.Line}:#{diagnostic.Col}</span>#{Escape(diagnostic.Message)}</button>")
      end
      if result.Error.Length > 0 && result.Diagnostics.Count == 0
        messages.Append("<pre class=error>#{Escape(result.Error)}</pre>")
      end
      output = result.Output.Length == 0 ? "<span class=muted>No console output.</span>" : Escape(result.Output)
      status = result.Success ? "Completed" : "Error"
      status_class = result.Success ? "result-status" : "result-status failed"
      value_html = result.HasValue ? "<div class=return-row><span>Result</span><code id=execution-value>⇒ #{Escape(result.Value)}</code><span class=value-type>#{Escape(result.ValueType)}</span></div>" : ""
      <<~HTML
        <div class="stage-scroll"><pre id="stage-code" tabindex="0">#{Escape(code)}</pre></div>
        <section class="console" aria-label="Console output" tabindex="0">
          <div class="console-head"><span>Console</span><span class="#{status_class}">#{status}</span></div>
          <pre id="console-output">#{output}</pre>
          #{value_html}
          <div id="diagnostics" role="status">#{messages.ToString}</div>
        </section>
      HTML
    end

    def self.Page() : String
      default_source = View.Escape(View.Example("pipeline"))
      options = StringBuilder.new
      for entry in View.Examples()
        parts = entry.Split("|")
        options.Append("<option value=\"#{parts[0]}\">#{View.Escape(parts[1])}</option>")
      end
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta name="theme-color" content="#f5efe0">
          <meta name="description" content="Write Alice, inspect HIR, MIR, C# and IL, and run it on .NET in your browser.">
          <link rel="canonical" href="https://play.alice-lang.org/">
          <meta property="og:url" content="https://play.alice-lang.org/">
          <meta property="og:title" content="Alice Playground — Follow your code.">
          <meta property="og:description" content="Write Alice, inspect HIR, MIR, C# and IL, and run it on .NET WebAssembly in your browser.">
          <link rel="icon" type="image/svg+xml" href="./brand/alice-icon.svg">
          <link rel="preload" href="./fonts/fraunces-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
          <title>Alice Playground</title>
          <style>
          @font-face{font-family:"Fraunces Variable";font-style:normal;font-display:swap;font-weight:100 900;src:url(./fonts/fraunces-latin-wght-normal.woff2) format("woff2-variations")}
          @font-face{font-family:"DM Sans";font-style:normal;font-display:swap;font-weight:400;src:url(./fonts/dm-sans-latin-400-normal.woff2) format("woff2")}
          @font-face{font-family:"DM Sans";font-style:normal;font-display:swap;font-weight:500;src:url(./fonts/dm-sans-latin-500-normal.woff2) format("woff2")}
          @font-face{font-family:"DM Sans";font-style:normal;font-display:swap;font-weight:600;src:url(./fonts/dm-sans-latin-600-normal.woff2) format("woff2")}
          :root{--ivory:#f5efe0;--paper:#fffcf4;--ink:#141210;--muted:#6f675d;--cherry:#c2183c;--cherry-dark:#a51231;--line:#e1d8c6;--night:#211e1b;--night-2:#2a2622;--night-line:#3b3530;--glow:#f1d6bd;--mono:"JetBrains Mono",ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace;--display:"Fraunces Variable",Georgia,serif;
            --hl-kw:#b0123a;--hl-fn:#1d4fa8;--hl-ty:#0f7672;--hl-str:#3b7a1c;--hl-num:#b45d00;--hl-sym:#8a4fb5;--hl-com:#9a9184;--hl-ivar:#0f7672;--hl-const:#b0123a;
            font-family:"DM Sans",ui-sans-serif,system-ui,sans-serif;color:var(--ink);background:var(--ivory);font-synthesis:none;-webkit-font-smoothing:antialiased}
          *{box-sizing:border-box}body{margin:0;min-height:100dvh;background:radial-gradient(ellipse 60% 40% at 85% -5%,#e8b3a340,transparent 70%),var(--ivory)}button,select{font:inherit}button{cursor:pointer}button:disabled{cursor:default;opacity:.45}a{color:inherit;text-decoration:none}:focus-visible{outline:2px solid var(--cherry);outline-offset:3px}::selection{background:var(--cherry);color:var(--ivory)}
          .skip{position:fixed;top:-60px;left:12px;background:var(--ink);color:var(--ivory);padding:10px 14px;z-index:9}.skip:focus{top:12px}
          header{height:84px;display:flex;align-items:center;justify-content:space-between;max-width:1600px;margin:auto;padding:0 36px;border-bottom:1px solid #14121022;gap:16px}
          .identity{display:flex;gap:12px;align-items:center;min-width:0}.wordmark{display:inline-flex;align-items:center;gap:5px}.wordmark img{width:38px;height:38px}.wordmark span{font:600 31px/1 var(--display);letter-spacing:-2px}.dot{color:var(--cherry)}.chip{font:500 11px var(--mono);border:1px solid #14121022;border-radius:999px;padding:5px 10px;background:#ffffff70}.chip b{color:var(--cherry);font-weight:600}
          nav{display:flex;gap:26px;font-size:13px;font-weight:500;align-items:center}nav a:hover{color:var(--cherry)}.gh{display:inline-flex;align-items:center;gap:7px;border:1px solid #14121026;border-radius:999px;padding:8px 13px;background:#ffffff4d;font-size:12px}.gh:hover{border-color:#c2183c66}
          main{max-width:1600px;padding:26px 36px 18px;margin:auto}
          .intro{display:flex;align-items:flex-end;justify-content:space-between;gap:24px;margin-bottom:20px}.eyebrow{display:inline-flex;align-items:center;gap:9px;font-size:10px;font-weight:600;letter-spacing:1.8px;color:#14121099}.diamond{width:7px;height:7px;background:var(--cherry);transform:rotate(45deg)}
          .intro h1{font:400 clamp(30px,3.3vw,44px)/1.05 var(--display);letter-spacing:-1.6px;margin:8px 0 0}.intro h1 em{color:var(--cherry);font-style:italic}.intro p{color:var(--muted);font-size:13px;margin:0;max-width:430px;line-height:1.7}
          .toolbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;gap:12px;flex-wrap:wrap}.left,.actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
          .example-label{display:flex;align-items:center;gap:10px;color:var(--muted);font-size:12px}select{appearance:none;border:1px solid #d3c8b4;border-radius:8px;padding:9px 34px 9px 12px;background:var(--paper) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6'%3E%3Cpath d='M1 1l4 4 4-4' stroke='%23141210' fill='none'/%3E%3C/svg%3E") no-repeat right 12px center;color:var(--ink);font-size:12px;min-width:200px}
          button.control{font-size:12px;font-weight:500;border:1px solid #d3c8b4;padding:9px 14px;border-radius:8px;background:#ffffff80;color:var(--ink);display:inline-flex;align-items:center;gap:7px}button.control:hover:not(:disabled){border-color:#c2183c66;color:var(--cherry)}
          button.primary{background:var(--cherry);border-color:var(--cherry);color:#fff;box-shadow:inset 0 1px 0 #ffffff40,0 5px 12px -4px #c2183c66;font-weight:600}button.primary:hover:not(:disabled){background:var(--cherry-dark);color:#fff}.key{font:10px var(--mono);opacity:.7;margin-left:4px}.ghost{border-color:transparent!important;background:transparent!important}
          .workspace{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);min-height:380px;height:calc(100dvh - 300px);border:1px solid #d6cbb6;border-radius:14px;overflow:hidden;background:var(--paper);box-shadow:0 24px 50px -30px #4a2c1f55}
          .source-panel{display:flex;flex-direction:column;border-right:1px solid #e3d9c6;min-width:0;min-height:0;overflow:hidden}
          .panel-head{height:44px;flex-shrink:0;display:flex;align-items:center;justify-content:space-between;padding:0 16px;background:#f1ead9;font:11px var(--mono);color:#5f574d;border-bottom:1px solid #e3d9c6}.file-name{display:flex;align-items:center;gap:9px}.dots{display:inline-flex;gap:6px;margin-right:6px}.dots i{width:9px;height:9px;border-radius:50%;background:#d9cdb8}.dots i:first-child{background:#e3a3a3}.file-dot{color:var(--cherry)}
          .editor{flex:1;display:flex;min-height:0;overflow:hidden;position:relative}
          .gutter{font:12.5px/1.8 var(--mono);width:52px;margin:0;padding:20px 12px 20px 0;text-align:right;color:#b8ad9b;user-select:none;overflow:hidden;background:#faf5ea;border-right:1px solid #efe6d4;flex-shrink:0}.gutter .ln{display:block}.gutter .ln.current{color:var(--ink)}.gutter .ln.bad{color:var(--cherry);font-weight:600}.gutter .ln.bad::before{content:"●";font-size:8px;margin-right:5px;vertical-align:2px}
          .code{position:relative;flex:1;min-width:0;overflow:hidden}
          #highlight,textarea{margin:0;border:0;padding:20px 22px;font:12.5px/1.8 var(--mono);tab-size:2;white-space:pre;letter-spacing:0;word-spacing:0}
          #highlight{position:absolute;inset:0;pointer-events:none;color:var(--ink);overflow:hidden}#highlight code{display:block;font:inherit;will-change:transform}
          textarea{position:absolute;inset:0;resize:none;width:100%;height:100%;background:transparent;color:transparent;caret-color:var(--cherry);overflow:scroll;outline:none;overscroll-behavior:contain;scrollbar-gutter:stable}textarea::selection{background:#c2183c33;color:transparent}textarea:focus{box-shadow:inset 0 0 0 2px #c2183c22}
          .no-hl textarea{color:var(--ink)}.no-hl #highlight{display:none}
          .t-kw{color:var(--hl-kw);font-weight:500}.t-fn{color:var(--hl-fn)}.t-ty{color:var(--hl-ty)}.t-str{color:var(--hl-str)}.t-num{color:var(--hl-num)}.t-sym{color:var(--hl-sym)}.t-com{color:var(--hl-com);font-style:italic}.t-ivar{color:var(--hl-ivar)}.t-const{color:var(--hl-const)}
          .source-foot{height:32px;flex-shrink:0;border-top:1px solid #ece3d1;padding:0 14px;color:#9b917f;font:10px var(--mono);display:flex;align-items:center;justify-content:space-between;gap:10px}
          .output-panel{min-width:0;min-height:0;overflow:hidden;display:flex;flex-direction:column;background:var(--night);color:#e9e0d1}
          .tabs{height:44px;flex-shrink:0;display:flex;align-items:stretch;background:var(--night-2);border-bottom:1px solid var(--night-line);padding-left:8px}.tab{border:0;border-bottom:2px solid transparent;background:transparent;color:#a8a092;min-width:58px;font:11px var(--mono);padding:0 16px}.tab:hover{color:#f3eadc}.tab[aria-selected=true]{color:var(--glow);border-bottom-color:var(--cherry);background:#ffffff08}
          .stage-label{margin-left:auto;align-self:center;font:9px var(--mono);letter-spacing:1px;color:#8a8173;padding-right:16px;display:flex;gap:10px;align-items:center}#timing{color:var(--glow)}
          #result{display:flex;flex:1;flex-direction:column;min-height:0}.stage-scroll{flex:1;min-height:0;overflow:auto;padding:22px;overscroll-behavior:contain;scrollbar-gutter:stable}.stage-scroll pre{margin:0;font:11.5px/1.8 var(--mono);tab-size:4;white-space:pre;color:#e6dccb}
          .empty{color:#968c7c;font:12px/1.9 var(--mono);margin:0}.spinner{display:inline-block;width:10px;height:10px;border:2px solid #f1d6bd55;border-top-color:var(--glow);border-radius:50%;animation:spin .8s linear infinite;margin-right:8px;vertical-align:-1px}@keyframes spin{to{transform:rotate(360deg)}}
          .console{flex:0 0 200px;min-height:110px;max-height:46%;overflow:auto;background:#191715;border-top:1px solid var(--night-line);padding:0 20px 18px;overscroll-behavior:contain;scrollbar-gutter:stable}.console-head{display:flex;justify-content:space-between;position:sticky;top:0;background:#191715;padding:12px 0;font:10px var(--mono);letter-spacing:1px;color:#a39985;z-index:1}.result-status{color:#9cc29a}.result-status.failed{color:#f08ba1}
          #console-output{font:12px/1.8 var(--mono);white-space:pre;color:#ece3d4;margin:6px 0}.muted{color:#7c7366}
          .diagnostic{border:0;background:#3a1f26;color:#f6c3cf;display:block;width:100%;padding:10px 12px;text-align:left;font:11px/1.6 var(--mono);border-left:3px solid var(--cherry);border-radius:4px;margin-top:10px}.diagnostic:hover{background:#45232c}.diagnostic span{display:block;color:#d999a8;margin-bottom:4px}.error{white-space:pre-wrap;color:#f6c3cf;font:11px/1.8 var(--mono)}
          .return-row{display:flex;align-items:baseline;gap:12px;border-top:1px solid #36312b;padding:12px 0 0;margin-top:14px;font:10px var(--mono);color:#a39985}.return-row code{font:12px var(--mono);color:var(--glow);white-space:pre}.value-type{margin-left:auto;color:#8a7f6e}
          .stage-scroll::-webkit-scrollbar,.console::-webkit-scrollbar,textarea::-webkit-scrollbar{width:10px;height:10px}.stage-scroll::-webkit-scrollbar-thumb,.console::-webkit-scrollbar-thumb{background:#4f463d;border-radius:5px}.stage-scroll::-webkit-scrollbar-corner,.console::-webkit-scrollbar-corner{background:var(--night)}textarea::-webkit-scrollbar-thumb{background:#d6cab5;border-radius:5px}textarea::-webkit-scrollbar-corner{background:var(--paper)}
          footer{display:flex;justify-content:space-between;align-items:center;gap:15px;font:10px var(--mono);padding:14px 2px 0;color:#887e6f;flex-wrap:wrap}.runtime-state{display:flex;align-items:center;gap:7px}.led{width:7px;height:7px;background:#c4a46c;border-radius:50%;box-shadow:0 0 0 3px #c4a46c22}.runtime-state[data-state=ready] .led{background:#4f8a55;box-shadow:0 0 0 3px #4f8a5522}.runtime-state[data-state=error] .led{background:var(--cherry);box-shadow:0 0 0 3px #c2183c22}
          #notice{font-size:12px;color:var(--cherry);margin-top:10px;min-height:16px}
          .install{margin-top:22px;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:18px;align-items:center;border:1px solid #14121018;border-radius:14px;padding:18px 22px;background:#ffffff59}.install h2{font:400 22px/1.1 var(--display);letter-spacing:-.6px;margin:0 0 4px}.install h2 em{color:var(--cherry)}.install p{margin:0;color:var(--muted);font-size:12px;line-height:1.6}.install>div{min-width:0}
          .cmd code{white-space:nowrap;overflow-x:auto;flex:1;min-width:0}.cmd{display:flex;align-items:center;gap:10px;background:var(--night);color:var(--glow);border-radius:10px;padding:10px 10px 10px 16px;font:12px var(--mono);max-width:100%;overflow:auto}.cmd .p{color:#bf8179;user-select:none}.cmd button{border:1px solid #ffffff26;background:transparent;color:#e9e0d1;border-radius:6px;font-size:10px;padding:5px 9px}.cmd button:hover{border-color:#ffffff80}
          .seg{display:inline-flex;border:1px solid #14121022;border-radius:999px;padding:3px;margin-bottom:8px}.seg button{border:0;background:transparent;border-radius:999px;font-size:11px;padding:4px 11px;color:var(--muted)}.seg button[aria-pressed=true]{background:var(--ink);color:var(--ivory)}
          dialog{border:1px solid #14121022;border-radius:14px;padding:22px 26px;background:var(--paper);color:var(--ink);max-width:440px;box-shadow:0 30px 60px -20px #0006}dialog::backdrop{background:#1412104d;backdrop-filter:blur(2px)}dialog h2{font:400 24px var(--display);margin:0 0 12px}dialog table{border-collapse:collapse;width:100%;font-size:12px}dialog td{padding:6px 0;border-bottom:1px solid #efe6d4}dialog td:first-child{width:46%}kbd{font:11px var(--mono);border:1px solid #d6cbb6;border-bottom-width:2px;border-radius:4px;padding:1px 5px;background:#fff}
          .toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%) translateY(20px);opacity:0;background:var(--ink);color:var(--ivory);padding:10px 16px;border-radius:999px;font-size:12px;pointer-events:none;transition:opacity .2s,transform .2s}.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
          .complete{position:absolute;z-index:5;min-width:180px;max-width:320px;max-height:220px;overflow:auto;margin:0;padding:4px;list-style:none;background:var(--paper);border:1px solid #d6cbb6;border-radius:8px;box-shadow:0 14px 30px -12px #4a2c1f66;font:12px var(--mono)}.complete[hidden]{display:none}.complete li{padding:4px 8px;border-radius:5px;display:flex;justify-content:space-between;gap:12px;cursor:pointer;white-space:nowrap}.complete li small{color:#a39985;font-size:10px}.complete li[aria-selected=true]{background:var(--cherry);color:#fff}.complete li[aria-selected=true] small{color:#ffffffb0}
          .open-link{display:none;font-size:12px;font-weight:500;color:var(--muted)}.open-link:hover{color:var(--cherry)}
          body.embed{background:var(--paper)}body.embed header,body.embed .intro,body.embed .install,body.embed footer,body.embed .left,body.embed #share,body.embed #download,body.embed #compile,body.embed .skip{display:none}body.embed main{padding:0;max-width:none}body.embed .toolbar{margin:0;padding:6px 10px;border-bottom:1px solid #e3d9c6;background:#f1ead9;flex-wrap:nowrap}body.embed .open-link{display:inline}body.embed .workspace{height:calc(100dvh - 47px);min-height:0;border:0;border-radius:0;box-shadow:none}body.embed #notice{position:fixed;bottom:4px;left:12px;margin:0;font-size:11px}body.embed #notice:empty{display:none}
          body.embed:not(.stages) .tabs,body.embed:not(.stages) .stage-scroll{display:none}body.embed:not(.stages) .console{flex:1;max-height:none;border-top:0}
          @media(min-width:1600px){body:not(.embed) .workspace{height:720px}}
          @media(max-width:900px){header{padding:0 16px;height:68px}nav .hide-sm,.chip,.intro p,.stage-label span.label{display:none}main{padding:18px 16px}.workspace{grid-template-columns:1fr;height:auto;min-height:0}.source-panel{border-right:0;border-bottom:1px solid #e3d9c6;height:400px}.output-panel{height:560px}.key{display:none}.example-label>span{display:none}select{min-width:150px}.tab{padding:0 13px}.console{flex-basis:170px}.install{grid-template-columns:minmax(0,1fr)}.wordmark span{font-size:26px}}
          body.embed .panel-head{display:none}body.embed .toolbar{justify-content:flex-end}body.embed .actions{flex-wrap:nowrap}body.embed .key{display:none}
          @media(min-width:561px){body.embed .workspace{grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);height:calc(100dvh - 47px)}body.embed .source-panel{height:auto;border-right:1px solid #e3d9c6;border-bottom:0}body.embed .output-panel{height:auto}}
          @media(max-width:560px){body.embed .workspace{height:calc(100dvh - 47px);grid-template-rows:minmax(0,1fr) minmax(120px,45%)}body.embed .source-panel,body.embed .output-panel{height:auto}}
          @media(prefers-reduced-motion:no-preference){button,a{transition:background .12s,color .12s,border-color .12s}}
          </style>
          <script type="module" src="./main.js"></script>
        </head>
        <body>
          <a class="skip" href="#source">Skip to editor</a>
          <header>
            <div class="identity"><a class="wordmark" href="https://alice-lang.org" aria-label="Alice home"><img src="./brand/alice-mark.svg" alt="" width="38" height="38"><span>alice<span class="dot">.</span></span></a><span class="chip">playground · <b>v0.10.1</b></span></div>
            <nav aria-label="Resources"><a class="hide-sm" href="https://github.com/alicelanguage/alice/blob/main/docs/language.md" target="_blank" rel="noreferrer">Language guide ↗</a><a class="hide-sm" href="https://alice-lang.org">alice-lang.org</a><a class="hide-sm" href="#install">Install</a><button id="shortcuts" class="control ghost" type="button" aria-label="Keyboard shortcuts" title="Keyboard shortcuts">Keys</button><a class="gh" href="https://github.com/alicelanguage/alice" target="_blank" rel="noreferrer">GitHub ↗</a></nav>
          </header>
          <main>
            <div class="intro"><div><span class="eyebrow"><span class="diamond"></span> ALICE → HIR → MIR → C# → IL → .NET</span><h1>Follow your code. <em>All the way down.</em></h1></div><p>Write Alice on the left. Inspect every compiler stage on the right, then run the emitted IL on .NET WebAssembly. Nothing leaves your browser.</p></div>
            <div class="toolbar">
              <div class="left"><label class="example-label"><span>Start with</span><select id="examples" aria-label="Example program">#{options.ToString}</select></label></div>
              <div class="actions"><a id="open-playground" class="open-link" href="./" target="_blank" rel="noopener">Open in playground ↗</a><button id="share" class="control" type="button" title="Copy a link to this program">Share</button><button id="download" class="control" type="button" title="Download main.al">Download</button><button id="compile" class="control" disabled>Compile<span class="key">⇧↵</span></button><button id="run" class="control primary" disabled>▶ Run<span class="key">Ctrl ↵</span></button><button id="stop" class="control" disabled>Stop</button></div>
            </div>
            <div class="workspace">
              <section class="source-panel" aria-label="Alice source editor">
                <div class="panel-head"><span class="file-name"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span><span class="file-dot">◇</span>main.al</span><span>Alice</span></div>
                <div class="editor"><pre id="gutter" class="gutter" aria-hidden="true">1</pre><div class="code"><pre id="highlight" aria-hidden="true"><code></code></pre><ul id="complete" class="complete" role="listbox" aria-label="Completions" hidden></ul><textarea id="source" aria-label="Alice source code" aria-autocomplete="list" aria-controls="complete" spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="off">#{default_source}</textarea></div></div>
                <div class="source-foot"><span id="cursor">Ln 1, Col 1</span><span>UTF-8 · 2 spaces · Ctrl/ comments</span></div>
              </section>
              <section class="output-panel" aria-label="Compiler output">
                <div class="tabs" role="tablist" aria-label="Compiler stage"><button class="tab" role="tab" data-stage="hir" aria-selected="false">HIR</button><button class="tab" role="tab" data-stage="mir" aria-selected="false">MIR</button><button class="tab" role="tab" data-stage="csharp" aria-selected="true">C#</button><button class="tab" role="tab" data-stage="il" aria-selected="false">IL</button><span class="stage-label"><span id="timing"></span><span class="label">COMPILER OUTPUT</span></span></div>
                <div id="result" aria-live="polite"><div class="stage-scroll"><p class="empty"><span class="spinner"></span>Loading .NET…<br>Your code will compile and run here.</p></div></div>
              </section>
            </div>
            <footer><span class="runtime-state" id="runtime-state"><span class="led"></span><span id="status">Starting .NET WebAssembly…</span></span><span>Runs in your browser · Source stays on this device</span></footer>
            <div id="notice" role="status"></div>
            <section id="install" class="install" aria-labelledby="install-title">
              <div><h2 id="install-title">Take Alice <em>home.</em></h2><p>One command installs the latest release (and the .NET 10 SDK if needed). Then <code>alice</code> opens the REPL.</p></div>
              <div><div class="seg" role="group" aria-label="Platform"><button type="button" data-install="unix" aria-pressed="true">macOS / Linux</button><button type="button" data-install="windows" aria-pressed="false">Windows</button></div>
              <div class="cmd"><span class="p" id="install-prompt">$</span><code id="install-command">curl -fsSL https://alice-lang.org/install.sh | sh</code><button id="copy-install" type="button">Copy</button></div></div>
            </section>
          </main>
          <dialog id="keys" aria-labelledby="keys-title"><h2 id="keys-title">Shortcuts</h2><table>
            <tr><td><kbd>Ctrl</kbd>/<kbd>⌘</kbd> <kbd>↵</kbd></td><td>Compile &amp; run</td></tr>
            <tr><td><kbd>⇧</kbd> <kbd>↵</kbd></td><td>Compile only</td></tr>
            <tr><td><kbd>Tab</kbd> / <kbd>⇧</kbd> <kbd>Tab</kbd></td><td>Indent / outdent</td></tr>
            <tr><td><kbd>Ctrl</kbd> <kbd>/</kbd></td><td>Toggle comment</td></tr>
            <tr><td><kbd>↵</kbd></td><td>New line, keeps indentation</td></tr>
            <tr><td><kbd>Ctrl</kbd> <kbd>Space</kbd></td><td>Autocomplete (also while typing)</td></tr>
            <tr><td><kbd>Esc</kbd></td><td>Stop a running program</td></tr>
          </table><form method="dialog" style="margin-top:16px;text-align:right"><button class="control primary">Got it</button></form></dialog>
          <div id="toast" class="toast" role="status"></div>
        </body>
        </html>
      HTML
    end
  end
end
