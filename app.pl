#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::JSON qw(encode_json);
use Cwd;

# =============================================================
# EPTCS WebSocket Demo
# 模拟教授的 published.cgi，使用相同的文件结构和 findvalue 循环
# 但通过 WebSocket 分批推送，配合骨架屏实现渐进式加载
#
# 运行前先生成数据:  perl setup_data.pl
# 然后启动服务:      morbo app.pl
# 访问:              http://127.0.0.1:3000
# =============================================================

# ---- 教授原版的 findvalue 函数 (模拟) ----
# 原版在 Alogin/subroutines.pl 中
# 核心逻辑: 打开文件 -> 读取内容 -> 存入 %value
our %value;

sub findvalue {
    my ($filename) = @_;
    if (open(my $fh, '<', $filename)) {
        local $/;
        $value{$filename} = <$fh>;
        close($fh);
    } else {
        $value{$filename} = '';
    }
}

sub translate {
    # 教授原版的 translate 函数，处理特殊字符
    # 这里简化处理
    my $ref = \$_[0];
    $$ref =~ s/\\&aacute;/á/g;
    $$ref =~ s/\\&eacute;/é/g;
    $$ref =~ s/\\&ouml;/ö/g;
}

# ---- 首页路由 ----
get '/' => 'index';

# ---- WebSocket 路由 ----
# 核心: 和教授的 foreach 循环相同的文件读取逻辑
# 但每读完一批就通过 WebSocket 推送给浏览器
websocket '/ws' => sub {
    my $c = shift;
    $c->inactivity_timeout(300);

    $c->on(message => sub {
        my ($c, $msg) = @_;

        if ($msg eq 'fetch') {
            my $homedir = getcwd();

            # 读取 volume 列表 (和教授的代码一样)
            open(my $fh, '<', "Data/published") or return;
            my @volumes = split(/\n/, do { local $/; <$fh> });
            close($fh);
            chomp(@volumes);

            my $batch_size = 20;
            my $total = scalar @volumes;
            my $total_batches = int(($total + $batch_size - 1) / $batch_size);

            # ---- 关键：用 next_tick 递归处理每一批 ----
            # 不能用 for 循环！for 循环是同步的，会阻塞事件循环
            # 导致 WebSocket 消息发不出去
            # next_tick 让每批处理完后把控制权还给事件循环，
            # 事件循环就能把数据推给浏览器

            my $batch_num = 0;

            my $process_batch;
            $process_batch = sub {
                my $start = $batch_num * $batch_size;
                return if $start >= $total;  # 全部处理完

                my $end = $start + $batch_size - 1;
                $end = $#volumes if $end > $#volumes;
                my @batch_data;

                # ---- 教授那个 findvalue 循环 ----
                # 这一批的 20 个 volume，每个 chdir + 13次 findvalue
                for my $i ($start .. $end) {
                    my $v = $volumes[$i];

                    chdir "$homedir/Published/$v" or next;

                    # 和教授 published.cgi 完全一样的 findvalue 调用
                    findvalue("volume");
                    findvalue("prefix");    translate($value{prefix});
                    findvalue("fullname");  translate($value{fullname});
                    findvalue("acronym");
                    findvalue("place");     translate($value{place});
                    findvalue("date");
                    findvalue("affiliation");
                    findvalue("day");
                    findvalue("month");
                    findvalue("anno");
                    findvalue("editor");    translate($value{editor});

                    chdir "Papers/toc" or next;
                    findvalue("arxived");
                    findvalue("abstract");  translate($value{abstract});

                    # 处理编辑人名 (和教授代码一样)
                    my @editor = split("\n", $value{editor});
                    my $editors = '';
                    for my $j (0 .. $#editor) {
                        my ($first, $last, $suffix, $affiliation) = split("\t", $editor[$j]);
                        $editors .= "$first $last";
                        $editors .= " $suffix" if $suffix;
                        if ($j < $#editor - 1)    { $editors .= ', ' }
                        elsif ($j == $#editor - 1) { $editors .= ' and ' }
                    }

                    push @batch_data, {
                        volume   => $value{volume}+0,
                        title    => "Proceedings of the $value{prefix} $value{fullname}",
                        acronym  => $value{acronym},
                        editors  => $editors,
                        place    => $value{place},
                        date     => $value{date},
                        year     => $value{anno}+0,
                        arxived  => $value{arxived},
                    };

                    chdir $homedir;
                }

                # 发送这一批
                $batch_num++;
                $c->send(encode_json({
                    type    => 'batch',
                    batch   => $batch_num,
                    total   => $total_batches,
                    volumes => \@batch_data,
                }));

                # 最后一批？发完成信号
                if ($end >= $#volumes) {
                    $c->send(encode_json({ type => 'done', count => $total }));
                    return;
                }

                # 关键：用 next_tick 把下一批交给事件循环
                # 这样事件循环有机会把刚才的数据推给浏览器
                Mojo::IOLoop->next_tick($process_batch);
            };

            # 启动第一批
            Mojo::IOLoop->next_tick($process_batch);
        }
    });
};

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>EPTCS - Published Volumes</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Georgia, "Times New Roman", serif; background: #f5f5f0; color: #333; }
.header { background: #AAFF33; padding: 8px 16px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 6px; border-bottom: 2px solid #8acc20; }
.header-btn { cursor: pointer; padding: 4px 12px; border: 1px solid #888; font-size: 13px; font-family: inherit; }
.header-info { font-size: 12px; }
.header-info b { color: #333; }
h1 { text-align: center; margin: 20px 0 5px; font-size: 22px; color: #222; }
h2 { text-align: center; margin: 0 0 10px; font-size: 17px; color: #555; font-weight: normal; }
hr { border: none; border-top: 1px solid #999; margin: 0 20px 15px; }

.control-panel {
    max-width: 1100px; margin: 0 auto; padding: 8px 15px;
    background: #fff; border: 1px solid #ddd;
    font-size: 12px; line-height: 2;
    display: none;
}
.control-panel.visible { display: block; }
.control-panel label { cursor: pointer; margin-right: 12px; white-space: nowrap; }
.control-panel input[type="checkbox"] { margin-right: 3px; vertical-align: middle; }

.table-container { max-width: 1100px; margin: 0 auto; padding: 0 15px 30px; }
table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 1px 4px rgba(0,0,0,0.1); }
table th { background: #AAFF33; padding: 8px 12px; text-align: center; font-size: 14px; border: 1px solid #8acc20; }
table td { padding: 7px 12px; border: 1px solid #ccc; font-size: 13px; vertical-align: top; }
table td:first-child { text-align: center; width: 60px; font-weight: bold; color: #444; }
table td a { color: #0055aa; text-decoration: none; }
table td a:hover { text-decoration: underline; }
.editors { font-size: 12px; color: brown; margin-top: 3px; display: none; }
.editors.show { display: block; }
.vol-year { display: none; }
.vol-year.show { display: inline; }
.vol-place { display: none; }
.vol-place.show { display: inline; }

@keyframes shimmer { 0% { background-position: -400px 0; } 100% { background-position: 400px 0; } }
.skeleton { background: linear-gradient(90deg, #e8e8e8 25%, #f5f5f5 50%, #e8e8e8 75%); background-size: 400px 100%; animation: shimmer 1.5s ease-in-out infinite; border-radius: 3px; }
.skeleton-row td { padding: 10px 12px; }
.skeleton-num { width: 35px; height: 18px; margin: 0 auto; }
.skeleton-title { height: 14px; margin-bottom: 6px; }
.skeleton-title.w80 { width: 80%; } .skeleton-title.w60 { width: 60%; } .skeleton-title.w70 { width: 70%; } .skeleton-title.w50 { width: 50%; }
.skeleton-editor { height: 11px; width: 40%; margin-top: 8px; }

.status-bar { max-width: 1100px; margin: 0 auto 8px; padding: 0 15px; display: flex; align-items: center; gap: 10px; font-size: 12px; color: #888; min-height: 24px; }
.progress-bar { flex: 1; max-width: 200px; height: 4px; background: #e0e0e0; border-radius: 2px; overflow: hidden; }
.progress-fill { height: 100%; background: #AAFF33; border-radius: 2px; width: 0%; transition: width 0.3s ease; }
.ws-dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: #ccc; margin-right: 4px; vertical-align: middle; }
.ws-dot.loading { background: #FF9800; animation: pulse 1s infinite; }
.ws-dot.done { background: #4CAF50; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
.volume-row { animation: fadeIn 0.25s ease-out; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
</style>
</head>
<body>

<div class="header">
    <span class="header-info">
        <b>DOI:</b> <a href="https://doi.org/10.4204/EPTCS" target="_blank">10.4204/EPTCS</a>&nbsp;
        <b>ISSN:</b> 2075-2180
    </span>
    <button class="header-btn" style="background:#FFFF00" onclick="window.open('https://about.eptcs.org/','_blank')">EPTCS Home Page</button>
    <button class="header-btn" style="background:#AAFF33" id="controlBtn">Control Panel</button>
    <button class="header-btn" style="background:#00FFFF" onclick="window.open('https://forthcoming.eptcs.org/','_blank')">Forthcoming Volumes</button>
</div>

<div class="control-panel" id="controlPanel">
    <label><input type="checkbox" id="chkEditors"> Editors</label>
    <label><input type="checkbox" id="chkYear" checked> Year</label>
    <label><input type="checkbox" id="chkPlace"> Places</label>
    <label><input type="checkbox" id="chkNames" checked> Names</label>
    <label><input type="checkbox" id="chkProc"> Proc.</label>
    <label><input type="checkbox" id="chkAbstract"> Abstracts</label>
    <label><input type="checkbox" id="chkExternal"> External links</label>
</div>

<h1>Electronic Proceedings in Theoretical Computer Science</h1>
<h2>Published Volumes</h2>
<hr>

<div class="status-bar">
    <span class="ws-dot" id="wsDot"></span>
    <span id="statusText">Connecting...</span>
    <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
    <span id="countText" style="font-size:11px; color:#aaa;"></span>
</div>

<div class="table-container">
    <table>
        <thead><tr><th>EPTCS</th><th>Contents</th></tr></thead>
        <tbody id="tableBody"></tbody>
    </table>
</div>

<script>
document.getElementById('controlBtn').addEventListener('click', function() {
    document.getElementById('controlPanel').classList.toggle('visible');
});
document.querySelectorAll('.control-panel input[type="checkbox"]').forEach(function(cb) {
    cb.addEventListener('change', applyFilters);
});
function applyFilters() {
    var showEd = document.getElementById('chkEditors').checked;
    var showYr = document.getElementById('chkYear').checked;
    var showPl = document.getElementById('chkPlace').checked;
    document.querySelectorAll('.editors').forEach(function(el) { el.classList.toggle('show', showEd); });
    document.querySelectorAll('.vol-year').forEach(function(el) { el.classList.toggle('show', showYr); });
    document.querySelectorAll('.vol-place').forEach(function(el) { el.classList.toggle('show', showPl); });
}

function createSkeleton(n) {
    var tbody = document.getElementById('tableBody');
    var w = ['w80','w60','w70','w50'];
    var h = '';
    for (var i = 0; i < n; i++)
        h += '<tr class="skeleton-row"><td><div class="skeleton skeleton-num"></div></td>'
           + '<td><div class="skeleton skeleton-title '+w[i%4]+'"></div>'
           + '<div class="skeleton skeleton-title w50"></div>'
           + '<div class="skeleton skeleton-editor"></div></td></tr>';
    tbody.innerHTML = h;
}

// 页面加载后立即连接 WebSocket
createSkeleton(15);
var dot = document.getElementById('wsDot');
var status = document.getElementById('statusText');
dot.className = 'ws-dot loading';

var ws = new WebSocket('ws://' + window.location.host + '/ws');
var loaded = 0;

ws.onopen = function() {
    status.textContent = 'Connected. Reading folders...';
    ws.send('fetch');
};

ws.onmessage = function(e) {
    var data = JSON.parse(e.data);
    var showEd = document.getElementById('chkEditors').checked;
    var showYr = document.getElementById('chkYear').checked;
    var showPl = document.getElementById('chkPlace').checked;

    if (data.type === 'batch') {
        var tbody = document.getElementById('tableBody');
        if (data.batch === 1) tbody.innerHTML = '';

        data.volumes.forEach(function(v) {
            var tr = document.createElement('tr');
            tr.className = 'volume-row';
            var link = v.arxived || ('https://doi.org/10.4204/EPTCS.' + v.volume);
            tr.innerHTML = '<td>' + v.volume + '</td><td>'
                + '<a href="' + link + '" target="_blank">'
                + 'Proceedings of ' + v.title + '</a>'
                + ' (' + v.acronym + ')'
                + '<span class="vol-place' + (showPl ? ' show' : '') + '">, ' + v.place + '</span>'
                + '<span class="vol-year' + (showYr ? ' show' : '') + '">, ' + v.year + '</span>'
                + '<div class="editors' + (showEd ? ' show' : '') + '">'
                + '<span style="font-size:11px;color:#666">Edited by</span> ' + v.editors
                + '</div></td>';
            tbody.appendChild(tr);
            loaded++;
        });

        document.getElementById('progressFill').style.width = ((data.batch / data.total) * 100) + '%';
        document.getElementById('countText').textContent = loaded + ' volumes';
        status.textContent = 'Reading folders... batch ' + data.batch + '/' + data.total;
    }

    if (data.type === 'done') {
        dot.className = 'ws-dot done';
        status.textContent = data.count + ' volumes loaded (' + data.count + ' folders × 13 findvalue)';
        document.getElementById('progressFill').style.width = '100%';
        ws.close();
    }
};

ws.onerror = function() {
    dot.className = 'ws-dot';
    status.textContent = 'WebSocket error - is morbo running?';
};
</script>
</body>
</html>
