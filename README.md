## as-postalprime V1.0.1

### Player courier job
- Players with the courier job can clock on at the depot, rent a van, and deliver Postal Prime orders themselves.
- Home deliveries and locker orders can both be delivered by players. Couriers can claim, load and deliver orders, and can also take their own orders (`allowOwnOrders`).
- Pay, XP and levels. Higher levels unlock bigger boxes and vehicles.
- Vehicle rental deposit, with damage cost taken from the deposit and a full tank required on return.
- Fallbacks: if nobody claims an order, no courier is on duty, or the courier abandons the run, loses the job or disconnects, the order is handled automatically as before.
- Everything is validated on the server (job, duty, distance, vehicle capacity, box size, level).

### Parcels from other resources
- Parcels from [as-passport](https://github.com/ACE090812/as-passport), [as-birthcert](https://github.com/ACE090812/as-birthcert) and [as-drivingschool](https://github.com/ACE090812/as-drivingschool) now go through the depot board and can be delivered by couriers.
- Parcels no longer block shopping. They live in their own list, so you can order from Postal Prime while a passport, birth certificate or licence is on its way. Up to 10 waiting at once (`Config.order.maxParcels`).
- New `Config.courier.parcelDeliveries` option, with a switch per resource (`as-passport`, `as-birthcert`, `as-drivingschool`, `other`) or a plain `true` / `false`. Turn off any resource you don't run.
- `createParcel` now records which resource sent it.
- Old saved data is migrated automatically.

### Home delivery
- Orders can be delivered to the player's home (nolag_properties / qbx_properties).

### New custom UI
- All ox_lib menus, notifications, progress bars and dialogs are replaced with a custom Postal Prime UI (depot window, run list, HUD, confirmation dialogs).
- Notifications drop down from the top of the depot window when it is open.
- Postal Prime logo in the depot header.

### Config
- `Config.courier` (job, pay, XP, vehicles, depot locations, fallbacks, HUD).
- `Config.courier.lockerDeliveries`, `allowOwnOrders`, `parcelDeliveries`.
- `Config.order.maxParcels`.

### Related resources
All optional. Postal Prime runs without them.
- [as-passport](https://github.com/ACE090812/as-passport): passports and replacement IDs, delivered to a locker.
- [as-birthcert](https://github.com/ACE090812/as-birthcert): birth certificates, ordered on the government site and delivered to a locker.
- [as-drivingschool](https://github.com/ACE090812/as-drivingschool): driving school and replacement licences.
- [as-browser](https://github.com/ACE090812/as-browser): in-game phone browser with the government site that as-passport and as-birthcert order through.

### Notes
- Restart `as-postalprime` after updating.
- Start `as-postalprime` before `as-passport`, `as-birthcert` and `as-drivingschool`.
- Depot and locker coordinates are defaults. Adjust them for your map (`/ppcoords` helps).
- Not included: multi-order, a job centre to hand out the courier job, admin XP tools. English only.
- See the README for full setup.
