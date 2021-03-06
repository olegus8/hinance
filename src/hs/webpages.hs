-- Copyright 2015 Oleg Plakhotniuk
--
-- This file is part of Hinance.
--
-- Hinance is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Hinance is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Hinance.  If not, see <http://www.gnu.org/licenses/>.

module Hinance.WebPages (webpages) where
import Data.Char
import Data.Function
import Data.List
import Data.Map.Strict (fromAscList, (!))
import Data.Maybe
import Data.Time.Clock.POSIX
import Data.Time.Format
import Hinance.Bank.Type
import Hinance.Changes
import Hinance.Currency
import Hinance.Report
import Hinance.Shop.Type
import Hinance.User.Tag
import Hinance.User.Data
import Hinance.User.Type
import Text.Printf
import Text.Show.Pretty

cfgbdrcol = "#DDD"
cfgtxtcol = "#333"
cfgselcol = "#000"
cfgtagcatbg = "#777"
cfgtagcatfg = "#FFF"
cfgselwidth = 5
cfgbdrround = 8 :: Integer
cfgcellwidth = 70 :: Integer
cfgcellspace = 10
cfgmarkheight = 30 :: Integer
cfgmarkspace = 10
cfgmarkofsx = 35
cfgmarkofsy = 20
cfgmarginleft = 5
cfgmarginright = 5
cfgmargintop = 5
cfgmarginbottom = 5
cfgcolumnheight = 400

stepmonth = 365 * 2 * 3600

webpages time = concatMap (devicepages time) [
  Device{dname="dtp", dlen=16, drows=50, dnarrow=False},
  Device{dname="mob", dlen=5, drows=10, dnarrow=True}]

data Device = Device {dname::String, dlen::Integer, drows::Integer,
                      dnarrow::Bool}

devicepages :: String -> Device -> [(String, String)]
devicepages time dev = [homepage time dev, diagpage time dev,
  bankspage time dev, shopspage time dev] ++ slicespages ++ groupspages where
  groupspages = [grouppage time dev $ toInteger i
                | i <- [0 .. length idxToGroup - 1]]
  slicespages = concat $
    [slicepages s (show i) | (i, s) <- zip idxs slices] ++
    [slicepages (tagslice t) (show t) | t <- [minBound::Tag ..]]
  slicepages :: Slice -> String -> [(String, String)]
  slicepages slice nslice = concat
    [[slicefigure time dev slice nslice step ofs nfig chgs posneg
     | (nfig, chgs, posneg) <- [("act", chgsact, True),
                                ("diff", chgsdiff, False),
                                ("plan", chgsplan, True)]] ++
     [slicepage time dev slice nslice step ofs icol categ
     | icol <- [ofs..ofs+len], categ <- scategs slice]
    | step <- steps len, ofs <- offsets len step]
  len = dlen dev

homepagename dev = printf "%s-home.html" (dname dev)

diagpagename :: Device -> String
diagpagename dev = printf "%s-diag.html" (dname dev)

bankspagename :: Device -> String
bankspagename dev = printf "%s-banks.html" (dname dev)

shopspagename :: Device -> String
shopspagename dev = printf "%s-shops.html" (dname dev)

grouppagename :: Device -> Integer -> String
grouppagename dev igroup = printf "%s-group%i.html" (dname dev) igroup

slicepagename :: Device->String->Integer->Integer->Integer->Integer->String
slicepagename dev nslice step ofs icol icat =
  printf "%s-slice%s-step%i-ofs%i-col%i-cat%i.html"
  (dname dev) nslice step ofs icol icat

slicefigname :: Device -> String -> Integer -> Integer -> String -> String
slicefigname dev nslice step ofs nfig =
  printf "%s-slice%s-step%i-ofs%i-nfig%s.svg" (dname dev) nslice step ofs nfig

homepage time dev = (homepagename dev, content) where
  content = html [] $ basicpage time dev $ (accsinfo dev) ++ suminfo

accsinfo dev = "<h3>Accounts</h3>" ++ inner where
  inner | dnarrow dev = innernarrow | otherwise = innerwide
  innerwide =
    "<table class=\"table table-striped\">" ++
      "<thead><tr>" ++
        "<th>Bank</th>" ++
        "<th>Account</th>" ++
        "<th>Balance</th>" ++
        "<th>Credit Limit</th>" ++
        "<th>Minimum Payment</th>" ++
        "<th class=\"text-right\">Pay Date</th></tr></thead>" ++
        "<tbody>" ++ (concatMap rowwide allbaccs) ++ "</tbody></table>"
  innernarrow =
    "<table class=\"table table-striped\">" ++
      "<tbody>" ++ (concatMap rownarrow allbaccs) ++ "</tbody></table>"
  rowwide (b, a) =
    "<tr><td>" ++ b ++ "</td>" ++
        "<td>" ++ (label a) ++ "</td>" ++
        "<td>" ++ (balance a) ++ "</td>" ++
        "<td>" ++ (cardlim a) ++ "</td>" ++
        "<td>" ++ (paymin a) ++ "</td>" ++
        "<td class=\"text-right\">" ++ (paytime a) ++ "</td></tr>"
  rownarrow (b, a) = "<tr><td>" ++
    (printf "<p><big><strong>%s:%s</strong> %s</big></p>"
                                  b (baid a) (label a)) ++
    (accinfo a) ++ "</td></tr>"
  accinfo a
    | bacard a =
      (printf "<p><big>Balance / Limit: <strong>%s / %s</strong></big></p>"
                                                   (balance a) (cardlim a)) ++
      (printf "<p><big>Minimum Payment: <strong>%s on %s</strong></big></p>"
                                                     (paymin a) (paytime a))
    | otherwise = "<p><big><strong>" ++ (balance a) ++ "</strong></big></p>"
  label a = filter isAscii $ balabel a
  balance a = fmtamount (babalance a) (bacurrency a)
  cardlim BankAcc{balimit=Nothing} = "unknown"
  cardlim BankAcc{balimit=Just lim, bacurrency=c} = fmtamount (- lim) c
  paymin BankAcc{bapaymin=Nothing} = "unknown"
  paymin BankAcc{bapaymin=Just pmin, bacurrency=c} = fmtamount pmin c
  paytime BankAcc{bapaytime=Nothing} = "unknown"
  paytime BankAcc{bapaytime=Just ptime} = fmtime "%Y-%m-%d" ptime
  allbaccs = concatMap (\x -> zip (repeat $ bid x) (baccs x)) banks

suminfo = "<h3>Summary</h3>" ++ inner where
  inner = concatMap row [
    ("Actual period", period actmin actmax),
    ("Planned period", period planfrom planto),
    ("Groups", sgroups),
    ("Banks", sbanks),
    ("Shops", sshops),
    ("Tags", show $ length alltags)]
  row (key, val) = printf "<p><big><strong>%s:</strong> %s</big></p>" key val
  period from to = printf "%s to %s" (date from) (date to)
  sgroups = printf "%i actual, %i planned" (ngroups chgsact) (ngroups planned)
  sbanks = printf "%i total, %i accounts, %i transactions"
                  (length banks) (length allbaccs) (length allbtrans)
  sshops = printf "%i total, %i orders, %i items"
                  (length shops) (length allsorders) (length allsitems)
  date = fmtime "%Y-%m-%d"
  ngroups = length . (groupSortBy cgroup)
  allbaccs = concatMap baccs banks
  allbtrans = concatMap batrans allbaccs
  allsorders = concatMap sorders shops
  allsitems = concatMap soitems allsorders
  alltags = [minBound::Tag ..]

diagpage time dev = (diagpagename dev, content) where
  content = html head $ basicpage time dev $ inner
  head = ["Diagnostics"]
  inner =
    (printf ("<h3>Raw data:</h3>" ++
      "<a href=\"%s\">shops</a>, <a href=\"%s\">banks</a>")
      (shopspagename dev) (bankspagename dev)) ++
    (printf "<h3>Checks (%i):</h3>" (length diagchecks)) ++
    (printf "<pre>%s</pre>" (ppShow diagchecks)) ++
    (printf "<h3>Changes without groups (%i):</h3>" (length diagnogrp)) ++
    (printf "<pre>%s</pre>" (ppShow diagnogrp)) ++
    (printf "<h3>Unbalanced groups (%i):</h3>" (length diagugrps)) ++
    (printf "<pre>%s</pre>" (ppShow diagugrps)) ++
    (printf "<h3>Slices mismatch (%i):</h3>" (length diagslicesflat)) ++
    (printf "<pre>%s</pre>" (ppShow diagslices))

bankspage time dev = (bankspagename dev, content) where
  content = html head $ basicpage time dev $ inner
  head = ["Banks"]
  inner = concatMap (\b -> concatMap (showacc b) $ baccs b) banks
  showacc b a = (printf "<h3>Bank %s, account %s</h3>" (bid b) (baid a)) ++
    (printf "<pre>%s</pre>" $ ppShow.diagtrans $ batrans a)

shopspage time dev = (shopspagename dev, content) where
  content = html head $ basicpage time dev $ inner
  head = ["Shops"]
  inner = "<h3>Shops</h3>" ++
    (printf "<pre>%s</pre>" (ppShow shops))

grouppage :: String -> Device -> Integer -> (String, String)
grouppage time dev igroup = (grouppagename dev igroup, content) where
  content = html head $ basicpage time dev $ inner
  head = [printf "Group %i" igroup]
  inner = slicetable dev (defstep len) 0 (len-1) changes "" ("Group: "++group)
  changes = filter (((==) group).cgroup) $ chgsact ++ chgsplan
  group = idxToGroup !! (fromIntegral igroup)
  len = dlen dev

slicepage :: String -> Device -> Slice -> String -> Integer ->
             Integer -> Integer -> SliceCateg -> (String, String)
slicepage time dev slice nslice step ofs icol categ =
  (slicepagename dev nslice step ofs icol icateg, content) where
  content = html head $ page time dev nslice step ofs icol $ inner
  head = [sname slice, fdate]
  inner = alert ++ buttons ++ figact ++ figdiff ++ figplan ++ tabact ++ tabplan
  alert | diagcount == 0 = ""
        | otherwise = printf (
          "<div class=\"alert alert-warning\">" ++
            "<strong>Warning!</strong> There are %i validation errors " ++
            "(<a href=\"%s\">read full report</a>).</div>")
          diagcount (diagpagename dev)
  buttons = "<div class=\"btn-group btn-group-lg btn-group-justified\">" ++
              olderbtn ++ stepbtns ++ newerbtn ++ "</div><br>"
  olderbtn = ofsbtn "Older" prevofs
  newerbtn = ofsbtn "Newer" nextofs
  ofsbtn title Nothing = printf
    "<a class=\"btn btn-lg btn-default disabled\">%s</a>" title
  ofsbtn title (Just newofs) = printf
    "<a class=\"btn btn-lg btn-default\" href=\"%s\">%s</a>"
    (slicepagename dev nslice step newofs (newofs+len-1) 0) title
  stepbtns = (concat [printf (
    "<a class=\"btn btn-lg btn-default\" href=\"%s\">%s</a>")
    (slicepagename dev nslice s (rcnofs s) ((rcnofs s)+len-1) 0) n
    | (s, n) <- zip (steps len) ["Months", "Actual"], s /= step])
  figact = fig "Actual" "act" chgsact
  figdiff = fig "Actual - Planned =" "diff" chgsdiff
  figplan = fig "Planned" "plan" chgsplan
  tabact = tab chgsact "act" "Actual"
  tabplan = tab chgsplan "plan" "Planned"
  fig = figpanel dev slice nslice step ofs icol icateg
  tab allchgs = slicetable dev step ofs icol changes where
    changes = ofschgs icol step $ catchgs categ $ slicechgs slice allchgs
  len = dlen dev
  prevofs | ofsidx > 0 = Just $ ofss !! (ofsidx-1) | otherwise = Nothing
  nextofs | ofsidx < ofslen-1 = Just $ ofss !! (ofsidx+1) | otherwise = Nothing
  ofslen = length ofss
  ofsidx = fromMaybe 0 $ elemIndex ofs ofss
  ofss = offsets len step
  rcnofs s = last $ takeWhile (\x -> x*s <= actmax-actmin) $ offsets len s
  icateg = toInteger $ fromMaybe 0 $ elemIndex categ $ scategs slice
  fdate = fmtime "%Y-%m" $ actmin + step*icol

figpanel :: Device -> Slice -> String -> Integer -> Integer ->
            Integer -> Integer -> String -> String -> [Change] -> String
figpanel dev slice nslice step ofs icol icateg title nfig allchgs =
  "<div class=\"panel panel-default\">" ++
    "<div class=\"panel-heading\">" ++
      "<h3 class=\"panel-title\">" ++ title ++ "</h3></div>"++
    "<div class=\"panel-body text-center\">" ++ fig ++
      "<ul class=\"list-inline\">" ++ labels ++ "</ul></div></div>" where
  fig = "<object type=\"image/svg+xml\" width=\"100%\" " ++
          (printf "id=\"hfig%s\" onload=\"%s\" data=\"%s\"></object>"
           nfig onload (slicefigname dev nslice step ofs nfig))
  onload :: String
  onload =
    (printf "var o=document.getElementById('hfig%s');" nfig) ++
    "var d=o.contentDocument;" ++
    (printf ("var c=d.getElementsByClassName('hcell-col%i-cat%i');" ++
             "var a=d.getElementsByClassName('hcell-act-col%i-cat%i');")
             icol icateg icol icateg) ++
    "for(var i=0;i<c.length;i++){c[i].setAttribute('style','display:none');}"++
    "for(var i=0;i<a.length;i++){a[i].removeAttribute('style');}"
  labels = concatMap label $ scategs slice
  label c = printf (
    "<li><span class=\"label\" style=\"color:%s;background-color:%s\"" ++
      ">%s: %i</span></li>") (scfg c) (scbg c) (scname c) (div amt 100) where
    amt = sum $ map camount $ catchgs c $ changes
  changes = slicechgs slice allchgs

slicetable :: Device -> Integer -> Integer -> Integer ->
              [Change] -> String -> String -> String
slicetable dev step ofs icolumn changes ntab title
  | null changes = "" | otherwise =
  "<div class=\"panel panel-default\">" ++
    "<div class=\"panel-heading\">" ++
      "<h3 class=\"panel-title\">" ++ title ++ visrange ++ "</h3></div>" ++
    pagination ++
    "<table class=\"table table-striped\">"++thead++tbodyvis++tbodyhid++
    "</table></div>" where
  tbodyvis =
    (printf "<tbody id=\"htabrows-%s\">" ntab) ++
      (concatMap row $ take irows $ reverse $ srtdate) ++ "</tbody>"
  tbodyhid =
    (printf "<tbody id=\"htabrows-hid-%s\" style=\"display:none\">" ntab) ++
      (concatMap row $ drop irows $ reverse $ srtdate) ++ "</tbody>"
  thead | dnarrow dev = "" | otherwise =
    "<thead><tr>" ++
      "<th>" ++ hsrtdate ++ "</th>" ++
      "<th>" ++ hsrtdesc ++ "</th>" ++
      "<th>" ++ hsrttags ++ "</th>" ++
      "<th>" ++ hsrtgroup ++ "</th>" ++
      "<th class=\"text-right\">" ++ hsrtamount ++ "</th>" ++ "</tr></thead>"
  visrange | lenchgs <= irows = printf " (showing all %i)" lenchgs
           | otherwise =
    (printf " (showing <span id=\"htabfrom-%s\">1</span>" ntab) ++
    (printf "...<span id=\"htabto-%s\">%i</span> " ntab irows) ++
    (printf "out of %i total)" lenchgs)
  pagination | lenchgs <= irows = "" | otherwise =
    "<div class=\"panel-body\">" ++
      "<div class=\"btn-group btn-group-lg btn-group-justified\">" ++
        btnprev ++ btnnext ++ "</div></div>"
  btnprev = btn False "prev" $ printf "Previous %i" irows
  btnnext = btn True "next" $ printf "Next %i" irows
  btn active nbtn text =
    (printf "<div class=\"btn-group\" %s id=\"htab%s-disabled-%s\">"
            (hideif active) nbtn ntab) ++
      "<button class=\"btn btn-lg btn-default\" disabled=\"disabled\">" ++
        text ++ "</div>" ++
    (printf "<div class=\"btn-group\" %s id=\"htab%s-%s\">"
            (hideif (not active)) nbtn ntab) ++
      "<button class=\"btn btn-lg btn-default\" " ++
        (printf "onclick=\"htab%s('%s',%i)\">%s</button></div>"
                nbtn ntab lenchgs text)
  hideif x | x = "style=\"display:none\"" | otherwise = ""
  hsrt title field = printf
    "<a href=\"#\" onclick=\"htabsrt('%s','%s',%i);return false\">%s</a>"
    ntab field lenchgs title
  row (change, ichange) =
    "<tr class=\"" ++
      (printf "htab-srtdate-%s-%i " ntab $ idx srtdate) ++
      (printf "htab-srtdesc-%s-%i " ntab $ idx srtdesc) ++
      (printf "htab-srttags-%s-%i " ntab $ idx srttags) ++
      (printf "htab-srtgroup-%s-%i " ntab $ idx srtgroup) ++
      (printf "htab-srtamount-%s-%i\"" ntab $ idx srtamount) ++
    ">" ++ rowcontent ++ "</tr>" where
    rowcontent
      | dnarrow dev = "<td>" ++
      "<p><big><strong>"++hsrtdate++":</strong> "++fdate++"</big></p>" ++
      "<p><big><strong>"++hsrtdesc++":</strong> "++desc++"</big></p>" ++
      "<p><big><strong>"++hsrttags++":</strong> "++tags++"</big></p>" ++
      "<p><big><strong>"++hsrtgroup++":</strong> "++group++"</big></p>" ++
      "<p><big><strong>"++hsrtamount++":</strong> "++amount++"</big></p></td>"
      | otherwise =
      "<td>" ++ fdate ++ "</td>" ++
      "<td>" ++ desc ++ "</td>" ++
      "<td>" ++ tags ++ "</td>" ++
      "<td>" ++ group ++ "</td>" ++
      "<td class=\"text-right\">" ++ amount ++ "</td>"
    desc | null url = label
         | otherwise = printf "<a href=\"%s\">%s</a>" url label
    group = printf "<a href=\"%s\">%i</a>"
      (grouppagename dev igroup) igroup
    tag t = printf "<a class=\"btn btn-default\" href=\"%s\">%s</a> "
      (slicepagename dev t step ofs icolumn 0) (drop 3 t)
    label = filter htmlSafe $ clabel change
    tags = concatMap tag $ sort $ map show $ ctags change
    igroup = groupToIdx ! (cgroup change)
    amount = fmtamount (camount change) (ccur change)
    fdate = fmtime "%Y-%m-%d" $ ctime change
    url = curl change
    idx xs = fromMaybe 0 $ elemIndex (change, ichange) xs
  srtdate = sortBy (on compare $ ctime.fst) ichanges
  srtdesc = sortBy (on compare $ clabel.fst) ichanges
  srtgroup = sortBy (on compare $ cgroup.fst) ichanges
  srtamount = sortBy (on compare $ camount.fst) ichanges
  srttags = sortBy (on compare $ concat.sort.(map show).ctags.fst) ichanges
  hsrtdate = hsrt "Date" "date"
  hsrtdesc = hsrt "Description" "desc"
  hsrttags = hsrt "Tags" "tags"
  hsrtgroup = hsrt "Group" "group"
  hsrtamount = hsrt "Amount" "amount"
  lenchgs = length changes
  ichanges = zip changes [0..]
  irows = fromIntegral $ (drows dev)

slicefigure time dev slice nslice step ofs nfig allchgs posneg =
  (slicefigname dev nslice step ofs nfig, content) where
  content = printf (
    "<svg xmlns=\"http://www.w3.org/2000/svg\" " ++
         "xmlns:xlink=\"http://www.w3.org/1999/xlink\" " ++
         "width=\"100%%\" height=\"100%%\" viewBox=\"0 0 %i %i\">%s</svg>")
    totalwidth totalheight $ concatMap column icolumns
  column icolumn = "<g>" ++
    "<g " ++
      (printf "transform=\"translate(%i,%i)\">%s</g>" x stackposy stackpos) ++
    "<rect " ++
      (printf "fill=\"none\" stroke=\"%s\" " cfgbdrcol) ++
      (printf "width=\"%i\" height=\"%i\" " cfgcellwidth cfgmarkheight) ++
      (printf "rx=\"%i\" ry=\"%i\" " cfgbdrround cfgbdrround) ++
      (printf "x=\"%i\" y=\"%i\"/>" x marky) ++
    "<text " ++
      (printf "text-anchor=\"middle\" fill=\"%s\" " cfgtxtcol) ++
      (printf "x=\"%i\" y=\"%i\">" (x + cfgmarkofsx) (marky + cfgmarkofsy)) ++
      (printf "%s</text>" fdate) ++
    "<g " ++
      (printf "transform=\"translate(%i,%i)\">%s</g>" x stacknegy stackneg) ++
    "</g>" where
    svgstack [] = ""
    svgstack (cell:cells) = "<g>" ++ justcell ++ tailcells ++ "</g>" where
      justcell = "<a target=\"_top\" xlink:href=\"" ++ href ++ "\">" ++
        "<rect style=\"display:none\" " ++
          (printf "class=\"hcell-act-col%i-cat%i\" " icolumn icateg) ++
          (printf "fill=\"%s\" " bgcolor) ++
          (printf "stroke=\"%s\" stroke-width=\"%i\" " cfgselcol cfgselwidth)++
          (printf "width=\"%i\" height=\"%i\" " cfgcellwidth heightact) ++
          (printf "x=\"0\" y=\"%i\" " (diry+cfgselwidth)) ++
          (printf "rx=\"%i\" ry=\"%i\"/>" cfgbdrround cfgbdrround) ++
        "<rect " ++
          (printf "class=\"hcell-col%i-cat%i\" " icolumn icateg) ++
          (printf "fill=\"%s\" stroke=\"%s\" " bgcolor cfgbdrcol) ++
          (printf "width=\"%i\" height=\"%i\" " cfgcellwidth height) ++
          (printf "x=\"0\" y=\"%i\" " diry) ++
          (printf "rx=\"%i\" ry=\"%i\"/>" cfgbdrround cfgbdrround) ++
        "<text " ++
          (printf "text-anchor=\"middle\" fill=\"%s\" " fgcolor) ++
          (printf "x=\"%i\" y=\"%i\">" cfgmarkofsx texty) ++
          (printf "%i</text></a>" (div amount 100))
      tailcells | null cells = ""
                | otherwise = (printf "<g transform=\"translate(0,%i)\">%s</g>"
                               nexty (svgstack cells))
      href = slicepagename dev nslice step ofs icolumn icateg
      bgcolor = scbg categ
      fgcolor = scfg categ
      amount = fcamount cell
      height = fcheight cell
      heightact = height - 2*cfgselwidth
      diry | amount > 0 = - height | otherwise = 0
      nexty | amount > 0 = - height | otherwise = height
      texty = diry + cfgmarkofsy
      categ = fccateg cell
      icateg = toInteger $ fromMaybe 0 $ elemIndex categ (scategs slice)
    stackpos = svgstack $ stackcells posamtftr poscatftr
    stackneg = svgstack $ stackcells negamtftr negcatftr
    stackcells amftr catftr =
      figurecells (scategs slice) normheight amftr catftr $ colchgs icolumn
    stackposy = cellsheightpos + cfgmargintop
    stacknegy = marky + cfgmarkspace + cfgmarkheight
    x = cfgmarginleft + ((icolumn-ofs) * cellwspace)
    marky = cfgmargintop + cellsheightpos + cfgmarkspace
    fdate = fmtime "%y-%m" $ ofstime icolumn step
  icolumns = [ofs..ofs+len-1]
  totalwidth = cfgmarginleft + (len*cellwspace) - cfgcellspace + cfgmarginright
  totalheight = cfgmargintop + cellsheightpos +
                cfgmarkspace + cfgmarkheight + cfgmarkspace +
                cellsheightneg + cfgmarginbottom
  cellwspace = cfgcellwidth + cfgcellspace
  cellsheightpos = maxcolheight normheight posamtftr poscatftr
  cellsheightneg = maxcolheight normheight negamtftr negcatftr
  normheight = maximum [1, normheightpos + normheightneg]
  normheightpos = maxcolheight cfgcolumnheight posamtftr poscatftr
  normheightneg = maxcolheight cfgcolumnheight negamtftr negcatftr
  posamtftr | posneg = (> 0) | otherwise = (/= 0)
  negamtftr | posneg = (< 0) | otherwise = (/= 0)
  poscatftr | posneg = (/= 0) | otherwise = (> 0)
  negcatftr | posneg = (/= 0) | otherwise = (< 0)
  maxcolheight scale amftr catftr = maximum $ map colheight icolumns where
    colheight = sum . (map fcheight) . cells . colchgs
    cells = figurecells (scategs slice) scale amftr catftr
  changes = slicechgs slice allchgs
  colchgs icolumn = ofschgs icolumn step $ changes
  len = dlen dev

steps len = [stepmonth, defstep len]

defstep len = div (actmax - actmin + len) len

actmin | null chgsact = 0 | otherwise = minimum $ map ctime chgsact
actmax | null chgsact = 0 | otherwise = maximum $ map ctime chgsact

offsets len step = sort $ past ++ future where
  past = [present, present-len .. 1] ++ [0]
  future = [present+len, present+2*len .. endplan]
  endplan = div (planto-actmin+step) step
  present = div (actmax-actmin+step) step

ofstime ofs step = actmin + (step * ofs)
ofschgs ofs step = filter (\Change{ctime=t} -> t >= tmin && t < tmax)
  where tmin = ofstime ofs step
        tmax = tmin + step

tagslice tag = Slice {sname=tagname, stags=[], scategs=[SliceCateg {
  scname = "Tagged with \"" ++ tagname ++ "\"",
  scbg=cfgtagcatbg, scfg=cfgtagcatfg, sctags=[tag]}]} where
  tagname = drop 3 $ show tag

fmtime format =
  (formatTime defaultTimeLocale format).posixSecondsToUTCTime.fromIntegral

htmlSafe x = (x /= '<') && (isAscii x)

groupToIdx = fromAscList $ zip idxToGroup idxs
idxToGroup = map head $ group $ sort $ map cgroup $ chgsact ++ chgsplan

data FigureCell = FigureCell {fccateg::SliceCateg, fcamount::Integer,
                              fcheight::Integer} deriving (Show, Read, Eq, Ord)

figurecells categs normh amftr catftr changes =
  sortBy (on compare $ abs.fcamount) $ filter cellftr $ map cell categs where
  cellftr = catftr . fcamount
  cell categ=FigureCell{fccateg=categ, fcamount=amount, fcheight=height} where
    amount = sum $ filter amftr $ map camount $ catchgs categ changes
    height = maximum [cfgmarkheight, div ((abs amount)*cfgcolumnheight) normh]

page time dev nslice step ofs icol content =
  (printf "<script>hdevrows=%i</script>" (drows dev)) ++
  "<div class=\"container\">" ++
    "<ul class=\"nav nav-pills\">" ++ navs ++ "</ul>" ++
    "<div class=\"row\"><div class=\"col-md-12\">" ++ content ++
      "<hr><p class=\"text-muted text-right\">Generated on "++time++"</p>"++
  "</div></div></div>" where
  navs = concatMap nav $ zip idxs slices
  nav (i, Slice{sname=name})
    | show i == nslice = printf "<li class=\"active\"><a>%s</a></li>" name
    | otherwise = printf "<li><a href=\"%s\">%s</a></li>" href name where
    href = slicepagename dev (show i) step ofs icol 0

basicpage time dev = page time dev "" (defstep $ dlen dev) 0 ((dlen dev)-1)

html titles body =
  "<!DOCTYPE html><html lang=\"en\"><head>" ++
    "<meta charset=\"utf-8\">" ++
    "<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\">" ++
    "<meta name=\"viewport\" content=\"width=device-width, " ++
            "initial-scale=1\">" ++
    "<title>" ++ title ++ "</title>" ++
    "<link rel=\"stylesheet\" href=\"bootstrap.min.css\">"++
    "<link rel=\"stylesheet\" href=\"bootstrap-theme.min.css\">"++
    "</head>" ++
  "<body>" ++ body ++
    "<script src=\"jquery.min.js\"></script>" ++
    "<script src=\"bootstrap.min.js\"></script>" ++
    "<script type=\"text/javascript\" src=\"hinance.js\"></script>" ++
    "</body></html>" where
  title = concat $ intersperse " | " $ titles ++ ["Hinance"]

idxs = [(toInteger 0)..]
