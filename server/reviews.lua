-- Product reviews.

local track = PP.track
local findCatalogItem = PP.findCatalogItem
local ratingFor = PP.ratingFor
local hasPurchased = PP.hasPurchased

lib.callback.register('as-postalprime:getReviews', function(source, data)
    local cid = track(source)
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = T('err.badRequest') } end
    local entry = findCatalogItem(data.itemId)
    if not entry then return { ok = false, error = T('err.unknownItem') } end

    -- Marketplace listings have no reviews.
    if entry.listing then return { ok = true, rating = 0, reviewCount = 0, reviews = {}, canReview = false } end

    local rating, count = ratingFor(entry.id, entry.baseRating, entry.baseReviews)
    local list, mine = {}, nil
    local bucket = PPStore.reviews[entry.id]
    if bucket then
        for reviewCid, r in pairs(bucket) do
            local review = {
                name = r.name, rating = r.rating, title = r.title, body = r.body, createdAt = r.createdAt * 1000,
            }
            if cid and reviewCid == cid then
                mine = review
            else
                list[#list + 1] = review
            end
        end
        table.sort(list, function(a, b) return a.createdAt > b.createdAt end)
    end

    local pd = cid and PPStore.getPlayer(cid) or nil
    local canReview = pd and hasPurchased(pd, entry.id) and not mine or false

    return {
        ok = true,
        rating = rating,
        reviewCount = count,
        mine = mine,
        reviews = list,
        canReview = canReview and true or false,
    }
end)

lib.callback.register('as-postalprime:submitReview', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = T('err.badRequest') } end

    local entry = findCatalogItem(data.itemId)
    if not entry or entry.listing then return { ok = false, error = T('err.unknownItem') } end

    local pd = PPStore.getPlayer(cid)
    if not hasPurchased(pd, entry.id) then
        return { ok = false, error = T('err.reviewNeedsPurchase') }
    end

    local rating = tonumber(data.rating) or 5
    rating = math.max(1, math.min(5, math.floor(rating)))
    local title = tostring(data.title or ''):sub(1, 80)
    local body = tostring(data.body or ''):sub(1, 500)
    if title == '' then title = T('review.noTitle') end
    if body == '' then body = T('review.noBody') end

    PPStore.reviews[entry.id] = PPStore.reviews[entry.id] or {}
    PPStore.reviews[entry.id][cid] = {
        name = PPBridge.getCharacterName(source),
        rating = rating, title = title, body = body, createdAt = os.time(),
    }
    PPStore.saveReview(entry.id, cid)

    return { ok = true }
end)
